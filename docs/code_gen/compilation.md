# Compilation

**Compile** is the library's single primary entry point. It turns a **Descriptor** into a
**Generated Class**.

## Signature

```ruby
SerializersCodeGen.compile(
  descriptor,              # Descriptor
  output:,                 # :json or :hash
  config: Config.new(...)  # optional; defaults to library-default values
) # => Generated Class
```

**Compile** is a **pure function** of its inputs. Calling it twice with the same inputs
produces two independent, functionally-identical **Generated Classes**. No memoization is
done inside the library. Callers (Panko) cache at their discretion.

The module-level method is a thin facade around the **Compiler** class:

```ruby
def self.compile(descriptor, output:, config: Config.new)
  Compiler.new(descriptor, output:, config:).compile
end
```

**Compiler** drives the **Generator** (which uses the **Code Builder**) to produce source,
then materializes the source into a class via `module_eval`. See
[structure.md](structure.md) for the layered architecture and the same pattern for **Dump**.

## Output per call

One **Generated Class** is returned. A consumer that wants both JSON and Hash output for the
same **Descriptor** must call **Compile** twice — once per **Output Mode**.

```ruby
post_json = SerializersCodeGen.compile(post_descriptor, output: :json)
post_hash = SerializersCodeGen.compile(post_descriptor, output: :hash)
```

The two classes have identical public method names (`serialize_one`, `serialize_many`) but
different implementations specialized for their **Output Mode**. See [output-modes.md](output-modes.md).

## Composition of nested Associations

**Composition** is the architectural choice for handling **Associations**: each inner
**Descriptor** **Compile**s to its own **Generated Class**, and the parent's **Generated Class**
holds nested instances as ivars populated by its constructor.

```ruby
class PostSerializer_JSON
  def initialize(descriptor:)
    @comments_serializer = CommentSerializer_JSON.new(descriptor: descriptor.associations[0].descriptor)
    @author_serializer   = AuthorSerializer_JSON.new(descriptor: descriptor.associations[1].descriptor)
    # ... Callables hoisted to ivars
  end
end
```

Rationale:

1. Each method body stays small → YJIT/ZJIT compilation heuristics trigger reliably.
2. Every call site is monomorphic (`@comments_serializer._write_one(...)` always sees
   `CommentSerializer_JSON`).
3. Changing a nested **Descriptor** does not require regenerating every parent.
4. Dump output is human-readable: one file per **Descriptor** × **Output Mode**.

Inlining is explicitly rejected for v1. Opt-in inlining as a micro-optimization may revisit
in a future version once benchmarks identify dispatch as a real cost.

## Recursive Descriptors

Self-recursion (`Comment has_many :replies` → `Comment`) and mutual recursion
(A → B → A) are both supported. See "Recursive Descriptors" in [descriptor.md](descriptor.md)
for the data-shape contract.

**Compile**-time handling:

- **Compile** maintains an identity-keyed cache during recursive descent:
  `{descriptor.__id__ => generated_class}`. When the **Generator** walks an **Association**
  whose `descriptor` is already in the cache (including the currently-building one), it
  reuses the existing **Generated Class** reference instead of recursing further. One
  **Generated Class** per unique **Descriptor** in the tree, regardless of reference
  count.
- For **self-recursion**, the emitted constructor assigns `self` to the nested-Association
  ivar:

  ```ruby
  class CommentSerializer_JSON
    def initialize(descriptor:)
      @replies_serializer = self   # self-recursion detected at Compile
    end
  end
  ```

- For **mutual recursion**, the emitted constructors use the same build-time identity
  cache threaded through the recursive `.new` calls, so each unique **Descriptor** in
  the cycle produces exactly one **Generated Class** instance.

**Runtime** has no cycle detection on the **Record** graph. If the data itself is a
cycle (e.g., a comment whose replies include itself via bad data), serialization
recurses until the stack blows. Adding runtime depth-tracking would cost on the hot
path; keeping the record graph acyclic is the caller's contract.

Compile-time cycle handling (via the identity cache) is unrelated and always on.

## Record-access strategy

**Compile** emits different code depending on whether the **Descriptor**'s **Models** field
is set.

### Generic path — `models: nil`

One `_write_one` (JSON mode) / `_to_hash` (Hash mode) is emitted. Its body branches once
on the **Record** shape, with both field-emit shapes inlined under the branch arms:

```ruby
def _write_one(record, writer, context, scope, filters)
  if record.is_a?(Hash)
    writer.push_object
    writer.push_value(record["id"], "id")
    writer.push_value(record["title"], "title")
    # ...
    writer.pop
  else
    writer.push_object
    writer.push_value(record.id, "id")
    writer.push_value(record.title, "title")
    # ...
    writer.pop
  end
end
```

- One shape branch per `_write_one` entry, not per **Attribute**.
- Each branch arm is monomorphic end-to-end — every `record["id"]` call site in the Hash
  arm sees a single receiver class; same for `record.id` call sites in the method arm.
  The inline caches never see a mixed receiver.
- Inlining both arms (rather than dispatching to per-shape `_write_one_hash` /
  `_write_one_object` helpers) saves a method call per record — measurable on
  association-heavy single-record serialization.
- The method arm uses method dispatch and works for ActiveRecord models, plain Ruby
  objects, anything responding to the **Source** method.

Above `FUSED_DISPATCH_MAX_FIELDS` (64) **Fields**, the emit reverts to a dispatcher +
per-shape-helper split: `_write_one` branches on the **Record** shape and delegates to
`_write_one_hash` / `_write_one_object` (`_to_hash_hash` / `_to_hash_object` in Hash
mode), each helper carrying one field-emit body — same bytes per body as the fused arms,
only the wrapping differs. Fusion measured faster at every tested width under YJIT (lazy
basic-block versioning compiles only the executed arm), but it doubles the method's
source; the split above this width trades the small dispatch saving for halved
per-method source — insurance for method-granular JITs (ZJIT compiles whole methods) and
bounded code-region growth across apps with hundreds of **Generated Classes**.

### Specialized path — `models: [...]` set (all ActiveRecord)

When **Models** is set and all entries are ActiveRecord classes, **Compile** introspects
each class at compile time and classifies every **Attribute** via a three-step rule:

1. **Column-backed** (name appears in `Model.columns_hash`) → emit
   `record._read_attribute("title")`. This is the fastest access form on Ruby 4 + YJIT +
   AR 8.1 by a wide margin (see [research/ar_access_results.md](research/ar_access_results.md)):
   4.43M ips persisted / 4.13M non-persisted, 1 alloc/call, and the `_read_attribute` call
   dispatches through AR's type-cast path so enum columns correctly return mapped labels.
2. **Else, instance method exists** (name appears in `Model.instance_methods`) → emit
   `record.title` method dispatch.
3. **Else** → raise at **Compile** time with a message naming the missing attribute and
   the class.

#### Overrides are bypassed for column-backed attributes

If a user defines `def title; super.upcase; end` on a model whose `title` is a column,
the specialized path emits the column-access form and the user's override is NOT invoked.
Users who need a custom reader should declare the field as a **Method Attribute** instead.
This mirrors Panko's existing semantics and keeps the generated code straight-line.

Document this loudly in user-facing docs (Panko's DSL layer) so the trade is explicit.

#### STI and mixed class sets

When `models:` contains multiple classes (STI or otherwise), classify each **Attribute**
against **every** class in the set and take the intersection:

- Column-backed in every class → emit the column-access form.
- Instance method in every class (but not uniformly column-backed) → emit method dispatch.
- Neither in at least one class → raise at **Compile** time.

The classification is computed once during **Compile** and baked directly into the emitted
source; there is no runtime classification cache. For STI specifically, this means a
subclass that overrides a column reader downgrades that attribute across the whole
**Generated Class** — method dispatch wins whenever any class in the set lacks uniform
column-backing.

#### Other specialized-path invariants

- No Hash-access branch — **Models** implies the **Records** are instances of those classes.
- Constraint: the **Models** classes must be loaded at **Compile** time (usually true in
  Rails boot order; flag loudly if a class isn't loadable).
- AR attribute methods are generated lazily. **Compile** calls `Model.define_attribute_methods`
  defensively before introspecting so steps 1–3 see a fully-populated method table. The call
  is idempotent and thread-safe (verified byte-identical across Rails 7.2/8.0/8.1; see
  [research/define_attribute_methods_safety.md](research/define_attribute_methods_safety.md)).

### Non-AR class in `models`

If a class in **Models** isn't ActiveRecord, **Compile** falls back to `record.foo` method
dispatch. No Hash-access branch is emitted (the contract is still "**Records** are instances
of these classes").

## Constructor of the Generated Class

The **Generated Class** has exactly one constructor signature:

```ruby
klass.new(descriptor:)
```

The constructor reads every **Callable** from the **Descriptor** into a named ivar, and
instantiates every nested **Generated Class** with its corresponding sub-**Descriptor**.

This is the same shape in both in-memory compiled form and **Dump**ed form — one code path
in the **Generator**, no divergence between the two.

## What Compile does internally

1. Validate the **Descriptor** (arity of **Callables**, `kind` enum, `output` in `[:json, :hash]`).
2. If **Models** is set, introspect classes for specialized-path classification.
3. Recursively **Compile** nested **Descriptors** (depth-first, naturally). No cycle handling.
4. Ask the **Generator** for source code — one method per top-level public entry plus
   `_write_one` (JSON mode) / `_to_hash` (Hash mode) and `_release`
   (see [generated-class.md](generated-class.md)).
5. Inject the source into a fresh anonymous class via Ruby's standard class-level source
   injection API, with a synthetic path for backtraces. See [code-generation.md](code-generation.md).
6. Return the class.

No side effects beyond class creation; no registration in any global registry.
