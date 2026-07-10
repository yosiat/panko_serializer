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
    :parent_class,       # Class | nil — optional parent class the Generated Class inherits from
  )

  Attribute = Data.define(
    :name,    # Symbol — output key
    :source,  # Symbol — method called on the Record; defaults to name at normalization time
  )

  MethodAttribute = Data.define(
    :name,  # Symbol — output key
    :body,  # Symbol | Callable — Symbol-body dispatches on self when parent_class: is set; Callable invoked as body.call(record, context, scope); may return SKIP
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

### `Descriptor#parent_class`

An optional Ruby `Class` (or `nil`, the default) the emitted **Generated Class** inherits
from. Pre-S18 the **Generated Class** always inherited from `Object` (implicit parent on a
bare `class <Name>_<Mode>` declaration); S18 widens this so a caller can pass a
user-supplied class and have the **Generated Class** emit `class <Name>_<Mode> <
<parent_class.name>`. The trigger for the **`parent_class` dispatch** shape from
[merging-into-panko.md § Generated Class subclasses the user's Panko serializer](merging-into-panko.md#generated-class-subclasses-the-users-panko-serializer).

- `nil` (default): the **Generated Class** emits as a bare `class <Name>_<Mode>`, byte-
  identical to pre-S18 output. Every non-Panko caller stays on this shape — the new
  field is invisible.
- Non-`nil` `Class`: the **Generated Class** subclasses `parent_class`, and — when the
  **Descriptor** also declares a Symbol-body **Method Attribute** — `_write_one` /
  `_to_hash` prepend `@object = record; @context = context; @scope = scope` at the top of
  the method body so the user-defined `def` on the parent class can read those ivars on
  `self` (the Panko-shape contract; see [code-generation.md](code-generation.md) for the
  gating rationale). The class's fully-qualified `parent_class.name` is
  spliced into the emit verbatim, so namespaced classes (`Outer::Inner::Base`) resolve
  correctly at `module_eval` time. Anonymous classes (passed as `Class.new`) are out of
  scope — Panko's converter always sets a named class.

Pairs with the widened `MethodAttribute#body` contract below: Symbol-body **Method
Attributes** can only appear in a **Descriptor** whose `parent_class:` is non-`nil`,
because the Symbol resolves via direct method dispatch on the **Generated Class**
instance (which only reaches user methods when it subclasses the user's class).
`Validators::SymbolBodyDispatch` enforces the pairing at **Compile** time; structural
validation accepts a `Symbol` body unconditionally (the structural rule can't see the
owning **Descriptor**'s `parent_class:` at `MethodAttribute.new` time).

### `Attribute`

A direct field read from the **Record** via the **Source** method. `source` defaults to `name`
after normalization; both must be Symbols.

### `MethodAttribute`

A **Field** whose value comes from either a **Callable** or — when the owning
**Descriptor**'s `parent_class:` is non-`nil` — a `Symbol` naming a method on `self` (the
**Generated Class** instance, which subclasses `parent_class`).

- **`body` as a Callable** (today's contract): any Ruby callable — Proc, Lambda, `Method`
  object (bound). `UnboundMethod` is rejected (must be bound before inclusion in the
  **Descriptor**). Arity must be `0`, `1`, `2`, or `3`. See "Callable arity" below.
  Emitted as `value = @cb_<name>.call(record, context, scope)` (truncated to declared
  arity).
- **`body` as a Symbol** (S18 widening): the Symbol names a method on `parent_class` (or
  inherited / `prepend`-ed onto it). Emitted as `value = <method_name>` — bare-identifier
  call on `self`, no Callable indirection. Inside the method body, `@object` / `@context`
  / `@scope` are reachable as ivars set by the per-record ivar writes at the top of
  `_write_one` / `_to_hash`. The Symbol body axis is **only** for `MethodAttribute#body`;
  `Association#if` stays Callable-only.
- **Symbol-body legitimacy**: a `Symbol` body in a **Descriptor** with `parent_class: nil`
  raises `SerializersCodeGen::SymbolBodyError` at **Compile** time (the Symbol resolves on
  `self`, but with an implicit `Object` parent the method can't be reached). Validation
  lives in `Validators::SymbolBodyDispatch`, not in structural validation
  (`MethodAttribute.new` has no view of the owning **Descriptor**'s `parent_class:`).
- **Symbol-body method existence / arity**: deferred to runtime. **Compile** does not
  introspect `parent_class.instance_method(<sym>)`. A missing method surfaces as Ruby's
  `NameError` ("undefined local variable or method") at serialize time; wrong arity
  surfaces as `ArgumentError`. No scg-specific error class — the error vocabulary stays
  Ruby-native.
- **Return value semantics** (both body kinds): if the return value is `equal?` to
  `SerializersCodeGen::SKIP`, the field is omitted from the output (no key, no value).
  Any other value is serialized.

Callable bodies and Symbol bodies can coexist in the same **Descriptor** — the emitter
branches per **Method Attribute** on `body.is_a?(Symbol)`.

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
- `if`: an optional guard **Callable**. Arity `0`, `1`, `2`, or `3`; return truthy to
  include, falsy to omit. When falsy, the key is **omitted entirely** (not written as
  null). When `nil`, no guard is emitted and no runtime cost is paid. No `unless:` —
  use `if: ->(r, c) { !... }` for negation.

**`if:` contract**:

- **Must be pure.** Side effects are unsupported (logging, mutation, caching inside the
  callable). The library does not guarantee an environment suitable for them.
- **Called at most once per (Association, Record) per serialize call.** Callers can rely
  on this. Filter-dropped **Associations** skip the call entirely; otherwise it runs
  exactly once.
- **No ordering guarantee across Associations** within one **Record**.

## Callable arity

A **Callable** (Method Attribute `body` or Association `if:`) must declare one of four
arities:

| Arity | Invoked as                          | Use case                                                                              |
| ----- | ----------------------------------- | ------------------------------------------------------------------------------------- |
| `0`   | `cb.call`                           | Global checks (feature flags, env) that ignore the row.                               |
| `1`   | `cb.call(record)`                   | Derived from the **Record** only.                                                     |
| `2`   | `cb.call(record, context)`          | Derived from **Record** and **Context**.                                              |
| `3`   | `cb.call(record, context, scope)`   | Derived from **Record**, **Context**, and **Scope** (auth/viewer axis, peer of Context). |

Arity is introspected at **Compile** time (`callable.arity`). The **Generator** emits
the appropriate call expression specialized to that arity — zero runtime dispatch
overhead, zero unused-arg passing.

**Rejected shapes** (all raise `SerializersCodeGen::ArityError` at **Compile** time):

- Variadic / splatted (`->(*args) {...}`, arity `-1`, `-2`, `-3`, …).
- 4-or-more positional args (arity `≥ 4`).

Kept simple on purpose. Callers needing flexibility should rewrite to arity `0`, `1`,
`2`, or `3`. This avoids the "I wrote `|*|` and now the library can't tell what I meant"
class of bug.

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
- `Descriptor#parent_class`, if set, is a Ruby `Class`. `nil` is the default and stays
  on the bare-`class <Name>_<Mode>` emit shape.
- `Attribute#name`, `source` are Symbols.
- `MethodAttribute#body` is a `Symbol` or responds to `.call` (rejects `UnboundMethod`).
  The Symbol-vs-Callable choice is structural; the Symbol-body legitimacy check (must
  pair with `Descriptor#parent_class: non-nil`) runs semantically at **Compile** time
  (see below).
- `Association#kind` ∈ `{:has_one, :has_many}`.
- `Association#descriptor` is a **Descriptor**.
- `Association#if`, if set, responds to `.call` (Symbol axis is **MethodAttribute#body**
  only).

Failures raise `SerializersCodeGen::DescriptorError`.

### Semantic — at Compile, one pass before emitting

Walks the tree (with identity-based cycle handling, see "Recursive Descriptors" above):

- **Name uniqueness across Fields** at the same level — no two **Fields** (regardless of
  kind) may share a `name`. Violations raise `NameCollisionError`.
- **Source validity on the specialized path** — when **Models** is set, every
  **Attribute**'s `source` must be column-backed or an instance method on every class in
  **Models**. Violations raise `UnknownSourceError`.
- **Callable arity** — every **Callable** has arity `0`, `1`, `2`, or `3`. Violations
  raise `ArityError`. See "Callable arity" above. Symbol-body **Method Attributes** are
  skipped by this rule (Symbols have no `#arity`); their existence / arity is checked
  by Ruby's normal method resolution at serialize time.
- **Symbol-body dispatch** — a `MethodAttribute#body` that is a `Symbol` may only appear
  in a **Descriptor** whose `parent_class:` is non-`nil`. Violations raise
  `SymbolBodyError`.

All semantic errors are subclasses of `SerializersCodeGen::CompileError`.

## Frozen, shareable

Every node is frozen. The same **Descriptor** may be referenced from multiple parents
(e.g., `CommentDescriptor` used in `PostDescriptor.associations` and `UserDescriptor.associations`)
— **Composition** at **Compile** time still yields independent **Generated Classes** per
parent, but the underlying data is shared safely.
