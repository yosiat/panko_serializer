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

### `serialize_one(record, context: nil, scope: nil, filters: nil)`

Serializes a single **Record**.

```ruby
serializer.serialize_one(@post, context: request_env, scope: current_user, filters: nil)
```

- Returns a **String** in JSON mode, a **Hash** (with string keys by default) in Hash mode.
- `context:` is arbitrary user data threaded through to every **Callable**. May be `nil`.
  See [Context contract](#context-contract) below.
- `scope:` is a peer of `context:` — arbitrary user data threaded unmodified through every
  **Callable**. May be `nil`. See [Scope contract](#scope-contract) below.
- `filters:` prunes the output tree. See [filters.md](filters.md) for shape and semantics.
- `record` must be compatible with **Record** access for the **Descriptor** (see
  [compilation.md](compilation.md)).

When `Config#supports_root_key` is `true`, the signature gains an additional `root_key:` kwarg:

```ruby
serializer.serialize_one(@post, root_key: "post", context: ..., scope: ...)
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

### `serialize_many(records, context: nil, scope: nil, filters: nil)`

Serializes a collection.

```ruby
serializer.serialize_many(@posts, context: request_env, scope: current_user)
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

## Scope contract

**Scope** is a peer of **Context** — an arbitrary caller-supplied value threaded
unmodified through every **Callable** invocation. Byte-identical to **Context** in
behaviour but distinct in identity. Conventionally used for auth/viewer data
(e.g., `current_user`), in contrast to **Context** which is conventionally used for
environment data (e.g., request headers); the library does not enforce or rely on either
convention.

- **Type**: unconstrained. May be any Ruby value — the library never inspects it.
- **Default**: `nil`. A **Callable** that requires a non-nil **Scope** is enforcing a
  caller-side contract; the library passes whatever was supplied.
- **Reaches**: every **Method Attribute** body and every **Association** `if:` Callable
  whose declared arity is 3, in positional order `(record, context, scope)`. **Callables**
  with arity 0/1/2 keep their existing emit shape — `scope` never leaks into a 2-arity
  Callable's `context` slot.
- **Identity-preserving through Composition**: an inner **Generated Class** invoked
  through a nested `has_one` / `has_many` observes the same **Scope** identity
  (`equal?`) as the outer call. Recursive **Descriptors** (self and mutual) preserve
  identity at every depth.
- **Independence from Context**: **Scope** and **Context** are separate channels.
  Passing one without the other (`scope:` without `context:`, or vice versa) is
  supported; each defaults to `nil` independently.
- **Independence from Filter**: same as **Context** — **Scope** participates in
  **Callable** invocation, never in code generation or pruning decisions.

## Internal methods

### `_write_one(record, writer, context, scope, filters)` (JSON mode)

Threads the **Writer** through **Composition**. Called by this class's public methods and
by parent **Generated Classes** during nested serialization. Do not call directly.

### `_to_hash(record, context, scope, filters)` (Hash mode)

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
