# Goals & scope

## What this library is

A **Compile**-time code-generation engine for Ruby serializers. It takes a **Descriptor** —
a normalized data structure describing a serializer's shape — and produces a **Generated Class**
whose public methods serialize **Records** as fast as Ruby allows on modern runtimes (YJIT, ZJIT).

Think of it as a way to JIT-compile an existing serializer library. The library itself is
not a user-facing serializer.

## Host gem

**Panko.** Panko's user-facing DSL (`class PostSerializer < Panko::Serializer; attributes :id, ...`)
translates into **Descriptors** and feeds them into this engine. `Panko::CodeGen` is Panko's
internal code-gen core.

## Design priorities (in order)

1. **Runtime performance.** Emit Ruby that the YJIT/ZJIT compilers specialize aggressively —
   small monomorphic methods, stable ivar shapes, minimal branching on the hot path.
2. **Debuggability.** The **Generated Class** must be inspectable via console and **Dump**-able
   to a readable `.rb` file. Backtraces must point to stable synthetic or real paths.
3. **Flexibility where it costs nothing.** Design choices that cost nothing at runtime should
   favor consumer flexibility (e.g., **Callables** over method-name conventions).

## Non-goals

- **No user-facing DSL.** That is Panko's job. The **Descriptor** is the public input; any
  sugar for constructing one is a secondary, optional convenience.
- **No internal caching.** **Compile** is a pure function of (**Descriptor**, **Output Mode**,
  **Config**). The caller (Panko) owns memoization.
- **No polymorphic Associations in v1.** Deferred (see [deferred.md](deferred.md)).
- **No runtime mutation of Config or Descriptor.** Both are frozen at compile time.

## Supported runtimes

- **Ruby**: 3.4.x, 4.0.x
- **Rails**: 7.2, 8.0, 8.1 (ActiveRecord integration only — no engine or Railtie in v1)

Support-matrix should be structured so dropping a Rails version is mechanical.

## Output modes

Two **Output Modes** are supported:

- **`:json`** — produces a String using `Oj::StringWriter` (Oj is a C extension, not FFI).
- **`:hash`** — produces a Ruby Hash with string keys by default.

The consumer picks which one when calling **Compile**; each produces its own **Generated Class**.

## What a user of Panko sees

Nothing directly. They keep writing Panko serializers. Under the hood, Panko normalizes their
DSL into a **Descriptor**, calls **Compile**, caches the **Generated Class**, and invokes
its `serialize_one` / `serialize_many` methods.

## What a library author sees

```ruby
descriptor = Panko::CodeGen::Descriptor.new(
  name: "PostSerializer",
  model: Post,
  attributes: [Attribute.new(name: :id, source: :id)],
  method_attributes: [MethodAttribute.new(name: :full_title, body: Post.method(:full_title_for))],
  associations: [Association.new(kind: :has_many, name: :comments, source: :public_comments,
                                  descriptor: CommentDescriptor, if: nil)]
)

klass = Panko::CodeGen.compile(descriptor, output: :json, config: Config.new(...))
klass.new(descriptor: descriptor).serialize_one(post, context: current_user, filters: nil)
#=> "{\"id\":1,\"full_title\":\"...\",\"comments\":[...]}"
```
