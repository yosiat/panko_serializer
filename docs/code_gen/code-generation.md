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
    builder.line "def _write_one(record, writer, context, filters)"
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

A parallel `HashGenerator` exists for `:hash` mode.

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
2. A **synthetic path** like `"(serializers-code-gen: PostSerializer/json)"`. When the
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

Why ivars (not class constants set via `const_set`):

- **One code path between in-memory compile and Dump.** If class constants were used in
  memory, the **Dump**ed file would need a different shape (can't serialize a Proc back to
  Ruby source). Using ivars keeps both forms byte-identical.
- **YJIT/ZJIT perf delta is negligible.** Ivar-read-plus-Proc-call vs constant-read-plus-Proc-call
  are dominated by the Proc invocation itself. The overhead difference isn't the hot spot.
- **Stable ivar shape.** All ivars are set in the constructor; the object shape is stable
  from the moment it's returned, which is what YJIT/ZJIT want.

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
[open-questions.md](open-questions.md) for framework details).
