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

A **Field** whose value comes from a **Callable**.

- `body` may be any Ruby callable: Proc, Lambda, `Method` object (bound). `UnboundMethod`
  is rejected (must be bound before inclusion in the **Descriptor**).
- **Arity**: must be `0`, `1`, or `2`. See "Callable arity" below.
- Return value semantics: if the return value is `equal?` to `SerializersCodeGen::SKIP`,
  the field is omitted from the output (no key, no value). Any other value is serialized.

### `Association`

A **Field** that links to another **Descriptor**. The link may be to a different
**Descriptor**, or back to the same one (self-recursion) or to an earlier ancestor
(mutual recursion) — both are supported. See "Recursive Descriptors" below.

- `kind`: `:has_one` or `:has_many`. Flat Array (not split by kind) on the parent **Descriptor**
  to preserve declaration order in output — critical for deterministic JSON and golden-file tests.
- `source`: method called on the parent **Record** to fetch the related object (or collection).
  Defaults to `name`; override when the property name differs from the method name on the
  model (e.g., output key `:comments`, but method on `Post` is `:public_comments`).
- `descriptor`: the nested **Descriptor**. May be the same **Descriptor** object as the
  parent (self-recursion) or any **Descriptor** reachable via the tree.
- `if`: an optional guard **Callable**. Arity `0`, `1`, or `2`; return truthy to include,
  falsy to omit. When falsy, the key is **omitted entirely** (not written as null). When
  `nil`, no guard is emitted and no runtime cost is paid. No `unless:` — use `if: ->(r, c) { !... }`
  for negation.

**`if:` contract**:

- **Must be pure.** Side effects are unsupported (logging, mutation, caching inside the
  callable). The library does not guarantee an environment suitable for them.
- **Called at most once per (Association, Record) per serialize call.** Callers can rely
  on this. Filter-dropped **Associations** skip the call entirely; otherwise it runs
  exactly once.
- **No ordering guarantee across Associations** within one **Record**.

## Callable arity

A **Callable** (Method Attribute `body` or Association `if:`) must declare one of three
arities:

| Arity | Invoked as              | Use case                                                |
| ----- | ----------------------- | ------------------------------------------------------- |
| `0`   | `cb.call`               | Global checks (feature flags, env) that ignore the row. |
| `1`   | `cb.call(record)`       | Derived from the **Record** only.                       |
| `2`   | `cb.call(record, context)` | Standard — derived from **Record** and **Context**.    |

Arity is introspected at **Compile** time (`callable.arity`). The **Generator** emits
the appropriate call expression specialized to that arity — zero runtime dispatch
overhead, zero unused-arg passing.

**Rejected shapes** (all raise `SerializersCodeGen::ArityError` at **Compile** time):

- Variadic / splatted (`->(*args) {...}`, arity `-1`, `-2`, …).
- 3-or-more positional args (arity `≥ 3`).

Kept simple on purpose. Callers needing flexibility should rewrite to arity `0`, `1`, or
`2`. This avoids the "I wrote `|*|` and now the library can't tell what I meant" class
of bug.

## Recursive Descriptors

A **Descriptor** may reference itself through an **Association**, enabling natural trees
(e.g., `Comment has_many :replies` where the replies' **Descriptor** is the same
`Comment` **Descriptor**). Mutual cycles (A → B → A) are also supported.

- **Identity is key.** Recursion is detected via Ruby object identity (`.equal?`) on
  **Descriptor** instances — not structural equality. The same **Descriptor** object must
  be reused in the recursive position.
- **Compile** uses an identity-keyed cache during recursive descent: one **Generated
  Class** is produced per unique **Descriptor** in the tree, even if referenced multiple
  times. See [compilation.md](compilation.md).
- **Instantiation** uses the same identity-keyed cache: one **Generated Class** instance
  is built per unique **Descriptor** during construction. For self-recursion, the nested
  ivar (`@replies_serializer`) is assigned `self`.
- **Termination at runtime** is the caller's responsibility. The library does not bound
  recursion depth — if the **Record** graph is infinite (e.g., a cycle in the data), the
  **Generated Class** recurses until the stack blows. This mirrors `to_json` / `as_json`
  behavior and keeps the hot path free of depth checks.

## Record semantics

A **Record** is anything the **Generated Class** can read fields from. Supported shapes:

- **ActiveRecord instances**: accessed via the fastest available path given **Models**.
- **Ruby Hashes**: accessed via `record["key"]` (default) or `record[:key]` (via config).
- **Plain Ruby objects**: accessed via method dispatch (`record.foo`). Works in the
  generic path; not specialized.

**Missing-value behavior** (generic path):

- **Hash** — a missing key returns `nil`, matching Ruby's default `Hash#[]` semantics. No
  strict mode, no **Config** knob. Callers who need strictness check their own input.
- **Object** — a missing method raises `NoMethodError` from the emitted line. The
  backtrace's synthetic path identifies the **Generated Class** and the failing line
  maps to the specific **Field**. No library-level rescue, no pre-flight `respond_to?`.
  Kept simple — friendlier errors would cost per-**Field** overhead on the hot path, and
  the raw `NoMethodError` is already self-locating.

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

## Validation

Validation runs in two phases. Both phases raise from the library's structured error
hierarchy. See [errors.md](errors.md).

### Structural — eager, at `Data.new`

Cheap, one-time-per-construction checks on types and shapes:

- `Descriptor#name` is a non-empty String.
- `Descriptor#models`, if set, is an Array of Class objects.
- `Descriptor#attributes`, `method_attributes`, `associations` are Arrays of the right
  element type (all **Fields**).
- `Attribute#name`, `source` are Symbols.
- `MethodAttribute#body` responds to `.call`.
- `Association#kind` ∈ `{:has_one, :has_many}`.
- `Association#descriptor` is a **Descriptor**.
- `Association#if`, if set, responds to `.call`.

Failures raise `SerializersCodeGen::DescriptorError`.

### Semantic — at Compile, one pass before emitting

Walks the tree (with identity-based cycle handling, see "Recursive Descriptors" above):

- **Name uniqueness across Fields** at the same level — no two **Fields** (regardless of
  kind) may share a `name`. Violations raise `NameCollisionError`.
- **Source validity on the specialized path** — when **Models** is set, every
  **Attribute**'s `source` must be column-backed or an instance method on every class in
  **Models**. Violations raise `UnknownSourceError`.
- **Callable arity** — every **Callable** has arity `0`, `1`, or `2`. Violations raise
  `ArityError`. See "Callable arity" above.

All semantic errors are subclasses of `SerializersCodeGen::CompileError`.

## Frozen, shareable

Every node is frozen. The same **Descriptor** may be referenced from multiple parents
(e.g., `CommentDescriptor` used in `PostDescriptor.associations` and `UserDescriptor.associations`)
— **Composition** at **Compile** time still yields independent **Generated Classes** per
parent, but the underlying data is shared safely.
