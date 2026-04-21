# Descriptor

The **Descriptor** is the input to **Compile** — an immutable, normalized description of one
serializer. Everything else in the library is a function of it.

## Shape

All **Descriptor** types are `Data.define` classes. They are frozen, pattern-matchable, and
structurally comparable.

```ruby
module SerializersCodeGen
  Descriptor = Data.define(
    :name,               # String — used for the Generated Class name and backtrace identity
    :models,             # Array<Class> | nil — when set, unlocks compile-time specialization
    :attributes,         # Array<Attribute>
    :method_attributes,  # Array<MethodAttribute>
    :associations,       # Array<Association>
  )

  Attribute = Data.define(
    :name,    # Symbol — output key
    :source,  # Symbol — method called on the Record; defaults to name at normalization time
  )

  MethodAttribute = Data.define(
    :name,  # Symbol — output key
    :body,  # Callable — invoked as body.call(record, context); may return SKIP
  )

  Association = Data.define(
    :kind,        # :has_one | :has_many
    :name,        # Symbol — output key
    :source,      # Symbol — method on Record to fetch the related object(s); defaults to name
    :descriptor,  # Descriptor — recursive reference
    :if,          # Callable | nil — optional (record, context) -> bool guard
  )
end
```

## Field semantics

### `Descriptor#name`

A human-readable identifier (typically the matching Panko class's name, e.g., `"PostSerializer"`).
Used to:
- Name the **Generated Class** (`PostSerializer_JSON`, `PostSerializer_Hash`).
- Compose the synthetic path passed to the Ruby eval step for backtrace stability.
- Name the **Dump**ed file.

### `Descriptor#models`

An Array of Ruby classes, or `nil`.

- `nil`: no knowledge about **Record** shape. **Compile** emits the generic path (runtime
  Hash vs method-dispatch branch).
- `[SomeClass]` or `[Class1, Class2]` (STI): unlocks compile-time specialization for
  ActiveRecord columns. See [compilation.md](compilation.md).

Plural name; the array is ordered but order is not semantically meaningful.

### `Attribute`

A direct field read from the **Record** via the **Source** method. `source` defaults to `name`
after normalization; both must be Symbols.

### `MethodAttribute`

A field whose value comes from a **Callable**, invoked as `body.call(record, context)`.

- `body` may be any Ruby callable: Proc, Lambda, `Method` object (bound). `UnboundMethod`
  is rejected (must be bound before inclusion in the **Descriptor**).
- Arity requirement: must accept 2 positional args. Lambdas with wrong arity fail fast at
  **Descriptor** validation; Procs are lax.
- Return value semantics: if the return value is `equal?` to `SerializersCodeGen::SKIP`,
  the field is omitted from the output (no key, no value). Any other value is serialized.

### `Association`

A recursive reference to another **Descriptor**.

- `kind`: `:has_one` or `:has_many`. Flat Array (not split by kind) on the parent **Descriptor**
  to preserve declaration order in output — critical for deterministic JSON and golden-file tests.
- `source`: method called on the parent **Record** to fetch the related object (or collection).
  Defaults to `name`; override when the property name differs from the method name on the
  model (e.g., output key `:comments`, but method on `Post` is `:public_comments`).
- `descriptor`: the nested **Descriptor**. Recursion terminates on the caller's side (no
  cycle detection in v1).
- `if`: an optional guard **Callable**, `(record, context) -> truthy/falsy`. When falsy, the
  key is **omitted entirely** (not written as null). When `nil`, no guard is emitted and no
  runtime cost is paid. No `unless:` — use `if: ->(r, c) { !... }` for negation.

## Record semantics

A **Record** is anything the **Generated Class** can read fields from. Supported shapes:

- **ActiveRecord instances**: accessed via the fastest available path given **Models**.
- **Ruby Hashes**: accessed via `record["key"]` (default) or `record[:key]` (via config).
- **Plain Ruby objects**: accessed via method dispatch (`record.foo`). Works in the
  generic path; not specialized.

## `SKIP` sentinel

```ruby
module SerializersCodeGen
  SKIP = Object.new.freeze
end
```

Returned by a **Method Attribute** body to omit a field.

- Identity-compared via `equal?` — O(1), never collides with user data.
- Exposed as a module constant so consumers write `return SerializersCodeGen::SKIP`.

## Normalization

Callers are expected to pass fully-normalized **Descriptors**. Convenience builders (e.g.,
accepting a bare symbol `:id` as shorthand for `Attribute.new(name: :id, source: :id)`) are
out of scope for this library; that's a Panko-DSL concern.

Validation happens at `Data.new` time where feasible (arity checks for **Callables**,
`kind` enum check, etc.). Beyond that, the **Descriptor** is trusted.

## Frozen, shareable

Every node is frozen. The same **Descriptor** may be referenced from multiple parents
(e.g., `CommentDescriptor` used in `PostDescriptor.associations` and `UserDescriptor.associations`)
— **Composition** at **Compile** time still yields independent **Generated Classes** per
parent, but the underlying data is shared safely.

Cycles (e.g., `Author` → `Posts` → `Author`) are not supported in v1.
