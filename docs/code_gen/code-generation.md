# Code generation

This document covers *how* the **Compile** step turns a **Descriptor** into Ruby source
and then into a class.

The orchestration layer (**Compiler**) drives the **Generator**; **Generator** uses the
**Code Builder** to accumulate source; **Compiler** then materializes the source into a
class via `module_eval`. See [structure.md](structure.md) for the full layering and how
**Dump** shares the same generator path.

## Strategy: string templates via an internal Code Builder

The **Generator** builds up a Ruby source string via an internal **Code Builder** DSL.
**Compiler** installs it into a fresh class using Ruby's standard class-level source-injection
API (`Module#module_eval` / `Module#class_eval` with source-string, filename, and starting-line
arguments — the idiomatic Ruby codegen path, same as used by `ActiveModel::AttributeMethods`).

Not ERB. Not Liquid. Not an AST library.

Why:

- The emitted artifact **is** Ruby. There is no language gap where a template engine earns
  its keep — interpolating strings into Ruby is what we're doing anyway.
- Recursive generation over **Associations** is a natural recursive descent in Ruby.
- Indentation is a first-class concern, handled cleanly by the **Code Builder**.
- Emitter methods are unit-testable: "given this **Attribute**, this is the exact string."
- The generator becomes ~300 lines of plain Ruby with no external dependency.

## Code Builder

```ruby
class CodeBuilder
  def initialize
    @lines = []
    @indent = 0
  end

  def line(str = "")
    @lines << ("  " * @indent) + str
  end

  def indent
    @indent += 1
    yield
    @indent -= 1
  end

  def to_s
    @lines.join("\n")
  end
end
```

That's the entire primitive. Every **Generator** emitter method takes a **Code Builder**
and writes lines.

## Generator shape

One emitter method per descriptor node type, one top-level method per **Output Mode**.
Recursive descent:

```ruby
class JsonGenerator
  def emit_serializer_class(descriptor, builder)
    builder.line "class #{descriptor.name}_JSON"
    builder.indent do
      emit_constructor(descriptor, builder)
      emit_serialize_one(descriptor, builder)
      emit_serialize_many(descriptor, builder)
      emit_write_one(descriptor, builder)
    end
    builder.line "end"
  end

  def emit_write_one(descriptor, builder)
    builder.line "def _write_one(record, writer, context, scope, filters)"
    builder.indent do
      builder.line "writer.push_object"
      descriptor.attributes.each        { |a| emit_attribute(a, descriptor, builder) }
      descriptor.method_attributes.each { |m| emit_method_attribute(m, builder) }
      descriptor.associations.each      { |a| emit_association(a, builder) }
      builder.line "writer.pop"
    end
    builder.line "end"
  end

  # ... one emit_* method per node type
end
```

The sketch above is illustrative. In the shipped code the walk is emitted once —
`ClassEmitter` (class shell, constructor, recursion wiring) + `FieldWalk` (field
ordering + record frame) + the `RecordAccess` strategies — and everything
mode-divergent sits behind the **Sink** seam: `JsonSink` emits `writer.push_*`
forms, `HashSink` emits `result[key] = ...` forms. One walk, two adapters — the
two modes' structure cannot drift because only the leaf shapes differ.

## Source pragmas

Every emitted source string begins with:

```ruby
# frozen_string_literal: true
```

- Zero-cost win for the frozen string key literals used on every **Writer** `push_key` / Hash
  assignment.
- Forward-compat with Ruby 4.x default-frozen-literals behavior.

## Injecting source into a class

**Compiler** creates a fresh anonymous class (via `Class.new`) and installs the
generated source into it using the standard class-level source-injection call. Three
arguments are passed:

1. The source string.
2. A **synthetic path** like `"(Panko::CodeGen: PostSerializer/json)"`. When the
   class is **Dump**ed, the path becomes the real file path instead.
3. A starting line number of `1` (matching the emitted string's line numbering).

This mirrors what `ActiveModel::AttributeMethods`, Sequel, and other mature codegen users
do. No user-supplied strings are ever installed this way — all source is library-controlled,
emitted deterministically from the **Descriptor**.

## Callable hoisting: ivars, not class constants

Every **Callable** in the **Descriptor** (**Method Attribute** bodies, **Association** `if`
conditions) becomes an ivar populated by the **Generated Class**'s constructor from the
**Descriptor**:

```ruby
def initialize(descriptor:)
  @cb_full_title  = descriptor.method_attributes[0].body
  @cb_if_comments = descriptor.associations[0].if
  @comments_serializer = CommentSerializer_JSON.new(descriptor: descriptor.associations[0].descriptor)
end
```

Emitted call site:

```ruby
writer.push_value(@cb_full_title.call(record, context))
```

The call expression is specialized per **Callable** arity (validated in
`{0, 1, 2, 3}` by `callable_arity`). The four shapes are:

```ruby
@cb_<name>.call                            # arity 0
@cb_<name>.call(record)                    # arity 1
@cb_<name>.call(record, context)           # arity 2
@cb_<name>.call(record, context, scope)    # arity 3 (S17.2)
```

The arity-3 shape was added in S17.2 alongside the `scope:` kwarg on
`serialize_one` / `serialize_many` — `scope` is threaded positionally
through `_write_one` / `_to_hash` between `context` and `filters` and
into every nested **Association** call (`@<name>_serializer._write_one(record, writer, context, scope, child_filter)`).
Arity 2 keeps its existing `(record, context)` meaning — no `scope`
leak. Both **Callable** surfaces (**Method Attribute** body and
**Association** `if:`) share the same per-arity emit shape.

Why ivars (not class constants set via `const_set`):

- **One code path between in-memory compile and Dump.** If class constants were used in
  memory, the **Dump**ed file would need a different shape (can't serialize a Proc back to
  Ruby source). Using ivars keeps both forms byte-identical.
- **YJIT/ZJIT perf delta is negligible.** Ivar-read-plus-Proc-call vs constant-read-plus-Proc-call
  are dominated by the Proc invocation itself. The overhead difference isn't the hot spot.
- **Stable ivar shape.** All ivars are set in the constructor; the object shape is stable
  from the moment it's returned, which is what YJIT/ZJIT want.

## Per-record ivar writes — the bounded `parent_class` deviation

The "GC ivars are init-time constants" pattern above has one **bounded deviation**: when
the **Descriptor** declares a Symbol-body **Method Attribute**, the **Generator** emits
three per-record ivar writes at the top of `_write_one` / `_to_hash`:

```ruby
@object  = record
@context = context
@scope   = scope
```

These ivars are mutated **on every call** to `_write_one` / `_to_hash`, not set once in
the constructor. The deviation is intentional and exists to support the `parent_class`
dispatch shape from [merging-into-panko.md § Generated Class subclasses the user's Panko
serializer](merging-into-panko.md#generated-class-subclasses-the-users-panko-serializer):
a Symbol-body **Method Attribute** dispatches via `value = <method_name>` on `self`, and
the user-defined method on `parent_class` reaches `@object` / `@context` / `@scope` to
read the **Record** and threaded values. Without per-record writes, the user method
couldn't see the current record.

Bounded by three properties:

- **Gated on a Symbol-body Method Attribute.** **Descriptors** with no Symbol-body
  **Method Attribute** emit no ivar writes — ivar-set is init-time only and "GC ivars are
  init-time constants" holds. A Symbol-body method is the only code that runs on the
  **Generated Class** instance during a serialize — Callable bodies and `if:` guards
  receive `(record, context, scope)` as explicit args — so without one the writes would
  be pure per-record overhead.
- **Per-call deterministic write site.** When emitted, the writes are *always* the three
  lines above at the *top* of `_write_one` / `_to_hash`. The shape is invariant — no
  per-Field branching, no conditional emit, no other ivars added — so YJIT's object-shape
  cache stays stable across calls (the same three ivar slots are written every time).
- **One write site per record on both paths.** Specialized and Generic each emit the
  writes at the top of the single `_write_one` / `_to_hash` body — on the Generic path
  both field-emit shapes are inlined under the `is_a?(Hash)` branch of that one method
  (see [compilation.md](compilation.md)), so the writes happen exactly once, before the
  branch, and every Symbol-body method reached from either arm sees the correct
  `@object`. Above the Generic path's fused-dispatch threshold, where the per-shape
  helpers return, the helpers stay un-prepended — they inherit the ivars from the
  `_write_one` / `_to_hash` that called them.

**Self-recursion safety**: under the S8 `@<name>_serializer = self` shortcut a
self-recursive **Descriptor** uses one **Generated Class** instance across every depth,
but each entry into `_write_one` / `_to_hash` re-writes the ivars at the top of the
method body. Inner frames running *during* their own `_write_one` / `_to_hash` call
observe their own per-record ivars. The "load-bearing" K1 safety property: this is the
only shape that's safe for self-recursion without per-call snapshot/restore guards — the
rejected J (init-time dispatcher ivar) and A (thread-local dispatcher cache + Lambda
wrapper) shapes share a dispatcher across recursion depths and clobber `@object` mid-
walk in ways the user method can't recover from.

The checkin-side counterpart of these writes is `_release`, which nils the three ivars
before a pooled instance goes back on its stack — see
[generated-class.md](generated-class.md).

Bench: `/tmp/k1_ivar_bench/bench.rb` (2026-05-16, YJIT-on, Ruby 4.0.2). Single-record
`serialize_one` with `Oj::StringWriter`:

| Shape                                   | IPS                | ns/i | Allocations |
| --------------------------------------- | ------------------ | ---- | ----------- |
| Baseline (no ivar writes)               | 2.53M (±3.9%)      | 395  | 12          |
| Symbol-body (3 ivar writes prepended)   | 2.36M (±8.7%)      | 424  | 12          |

`benchmark-ips` verdict: "same-ish: difference falls within error". The ~29 ns delta is
within noise; allocations are identical (no extra object per call). Pinned at the
benchmark layer in S18.5 as a permanent regression guard.

## Backtrace quality

- The synthetic path shows up in `Method#source_location`, so console tools (Pry's
  `show-source`, IRB's `ls`) can display the generated source via the `method_source` gem.
- When **Dump**ed, the same code is in a real file — IDEs, debuggers, and stack traces
  all resolve to readable Ruby.
- Line numbers start at 1 for the synthetic-path case, matching the emitted string.

## Unit testing the Generator

Each emitter method is a pure function of (node, builder state) → output. Tests can:

1. Snapshot-test emitter outputs: "given this **Attribute**, assert the exact lines emitted."
2. Assert structural properties: "every `_write_one` opens with `writer.push_object` and
   closes with `writer.pop`."
3. Compile a fixture **Descriptor** and exercise the **Generated Class** against known inputs.

Snapshot tests on the generated source are the primary unit-test mechanism (see
[testing.md](testing.md) for the snapshot harness and tier rules).
