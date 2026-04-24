# The Generated Class

A **Generated Class** is the product of one **Compile** call. It exists per (**Descriptor**,
**Output Mode**) pair — e.g., `PostSerializer_JSON`.

## Constructor

```ruby
serializer = klass.new(descriptor: my_descriptor)
```

- Takes one kwarg: `descriptor:`. The same **Descriptor** used to **Compile** the class.
- Populates ivars for every hoisted **Callable** (Method Attribute bodies, Association
  `if:` conditions).
- Recursively constructs nested **Generated Class** instances for each **Association**.

Why `descriptor:` at the constructor and not at the class level? So the in-memory compiled
form and the **Dump**ed form have the exact same shape (one **Generator** code path, no
divergence).

## Public methods

### `serialize_one(record, context: nil, filters: nil)`

Serializes a single **Record**.

```ruby
serializer.serialize_one(@post, context: current_user, filters: nil)
```

- Returns a **String** in JSON mode, a **Hash** (with string keys by default) in Hash mode.
- `context:` is arbitrary user data threaded through to every **Callable**. May be `nil`.
  See [Context contract](#context-contract) below.
- `filters:` prunes the output tree. See [filters.md](filters.md) for shape and semantics.
- `record` must be compatible with **Record** access for the **Descriptor** (see
  [compilation.md](compilation.md)).

When `Config#supports_root_key` is `true`, the signature gains an additional `root_key:` kwarg:

```ruby
serializer.serialize_one(@post, root_key: "post", context: ...)
# => in JSON mode: {"post":{"id":1,...}}
# => in Hash mode: {"post" => {"id"=>1, ...}}
```

Passing `root_key: nil` (the default) skips wrapping. The generated method literally does
not have this kwarg when `supports_root_key: false` — callers who try to pass it get an
`ArgumentError`.

**Accepted values**: a non-empty String or `nil`. Anything else — an empty String, a
Symbol, or any non-String/non-nil value — raises `ArgumentError` at call time. The check
matches filters.md's convention for caller-error shapes (`:only` + `:except` at the same
level also raises `ArgumentError`).

### `serialize_many(records, context: nil, filters: nil)`

Serializes a collection.

```ruby
serializer.serialize_many(@posts, context: current_user)
```

- `records` must respond to `each` (typically an Array or an ActiveRecord::Relation).
- In JSON mode: emits `[...]` (a top-level array).
- In Hash mode: returns `Array<Hash>`.
- Same `root_key:` kwarg behavior as `serialize_one` when `Config#supports_root_key: true`.
  In JSON: `{"posts":[...]}`. In Hash: `{"posts" => [{...}, ...]}`.
- No auto-detection of "is this a single **Record** or a collection?" — the caller picks
  the method. Two explicit entry points avoid runtime type introspection and keep call sites
  monomorphic.

## Context contract

**Context** is the arbitrary caller-supplied value threaded unchanged through every
**Callable** invocation. The library reads it zero times and imposes zero structure on it.

- **Type**: unconstrained. May be any Ruby value — Hash, struct, request object, nil, a
  class instance, a Proc — the library never inspects it.
- **Default**: `nil`. Any **Callable** that requires a non-nil **Context** is enforcing a
  caller-side contract; the library passes whatever was supplied.
- **Independence from Filter**: **Context** and **Filter** are separate channels.
  The library does not extract filtering information from **Context**. Callers who want
  filters derived from context compute the filter Hash themselves and pass it via
  `filters:`. This keeps the **Generator**'s contract crisp: filters participate in code
  generation; context does not.

## Internal methods

### `_write_one(record, writer, context, filters)` (JSON mode)

Threads the **Writer** through **Composition**. Called by this class's public methods and
by parent **Generated Classes** during nested serialization. Do not call directly.

### `_to_hash(record, context, filters)` (Hash mode)

Returns a Hash. Called by this class's public methods and by parent **Generated Classes**
during nested serialization. Do not call directly.

Both internal methods operate on one **Record** and are idempotent/pure aside from **Writer**
mutations in JSON mode.

## Thread safety

A **Generated Class** instance holds ivars that are read but not mutated during serialization
(callables and nested instances). It is safe to share one instance across threads.

However, in JSON mode, the top-level `serialize_one` / `serialize_many` methods allocate a
fresh **Writer** on every call, so there is no mutable state shared between calls. **Composition**
also threads the **Writer** as a method parameter, not via an ivar — so nested serializers
are equally thread-safe.

## Instance lifecycle

Cheap to allocate; cheap to throw away. Callers may:

- Instantiate once and reuse forever (common).
- Instantiate per request (fine — constructor cost is small and ivar-population is straightforward).
- Pool per thread (overkill for v1 — benchmark first).

The library itself has no opinion.

## Naming in Ruby

The **Generated Class** is anonymous by default. Its `name` method returns `nil`. Its
`inspect` output and backtrace identity come from the synthetic path passed to the eval
step. If a consumer wants a stable name, they can `const_set` it into their own namespace.
The **Descriptor**'s `name` field is used only for the synthetic path and **Dump** output.
