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

## Record-access strategy

**Compile** emits different code depending on whether the **Descriptor**'s **Models** field
is set.

### Generic path — `models: nil`

`_write_one` dispatches to one of two specialized helpers based on the **Record** shape:

```ruby
def _write_one(record, writer, context, filters)
  if record.is_a?(Hash)
    _write_one_hash(record, writer, context, filters)
  else
    _write_one_object(record, writer, context, filters)
  end
end

def _write_one_hash(record, writer, context, filters)
  writer.push_object
  writer.push_key("id");    writer.push_value(record["id"])
  writer.push_key("title"); writer.push_value(record["title"])
  # ...
  writer.pop
end

def _write_one_object(record, writer, context, filters)
  writer.push_object
  writer.push_key("id");    writer.push_value(record.id)
  writer.push_key("title"); writer.push_value(record.title)
  # ...
  writer.pop
end
```

- One dispatch per `_write_one` entry, not per **Attribute**.
- Each helper is monomorphic end-to-end once entered — every `record["id"]` call site in
  `_write_one_hash` sees a single receiver class; same for `record.id` call sites in
  `_write_one_object`. YJIT/ZJIT specialize each helper as its own unit.
- The dispatch method body is small enough to inline under YJIT; when it doesn't, the one
  extra call is trivial vs. the per-attribute work inside.
- `_write_one_object` uses method dispatch and works for ActiveRecord models, plain Ruby
  objects, anything responding to the **Source** method.

### Specialized path — `models: [...]` set (all ActiveRecord)

When **Models** is set and all entries are ActiveRecord classes, **Compile** introspects
each class at compile time and classifies each **Attribute**:

| Classification                       | Emitted code                                  |
| ------------------------------------ | --------------------------------------------- |
| Column-backed, no reader override    | `record._read_attribute("title")`             |
| Column-backed, reader override       | `record.title`                                |
| Not column-backed (virtual, method)  | `record.title`                                |

- `_read_attribute` bypasses method dispatch but preserves AR type-casting — correct for
  columns without user overrides.
- STI: intersect the column sets across all **Models**; fall back to `record.title` for any
  attribute that isn't uniformly column-backed across the set.
- No Hash-access branch on the specialized path — **Models** implies the **Records** are instances of
  those classes.
- Constraint: the **Models** classes must be loaded at **Compile** time (usually true in
  Rails boot order; flag this clearly).

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
   `_write_one` (JSON mode) / `_to_hash` (Hash mode).
5. Inject the source into a fresh anonymous class via Ruby's standard class-level source
   injection API, with a synthetic path for backtraces. See [code-generation.md](code-generation.md).
6. Return the class.

No side effects beyond class creation; no registration in any global registry.
