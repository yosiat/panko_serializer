# Filters

A **Filter** is a caller-supplied inclusion/exclusion rule applied to the **Descriptor**
tree at serialize time to prune fields or **Associations**. Filters are passed per call
(not baked into the **Generated Class**) and thread through **Composition**.

## Public shape

`filters:` is a nested **Hash** keyed by symbols. `nil` means "no filtering — emit everything."

```ruby
serializer.serialize_one(
  @post,
  filters: {
    only:     [:id, :title],
    comments: { only: [:id, :body] },
    author:   { except: [:internal_notes] },
  },
)
```

### Keys at each level

| Key                             | Value                       | Meaning                                                                                  |
| ------------------------------- | --------------------------- | ---------------------------------------------------------------------------------------- |
| `:only`                         | `Array<Symbol>`             | Allowlist. Only listed Fields emit — **Attribute** / **Method Attribute** names, **Association** **Source**s. |
| `:except`                       | `Array<Symbol>`             | Denylist. Listed keys (same key kinds as `:only`) are omitted. Everything else emits.                                |
| any other symbol                | `Hash` (same shape, nested) | Child filter for the **Association** whose **Source** matches the key.                    |

### Rules

- `:only` and `:except` at the same level are **mutually exclusive**. Supplying both is a
  caller error: the engine raises `ArgumentError` when the **Filter** is built (`Filter.wrap`
  at the `serialize_one` / `serialize_many` entry, depth-first across the Hash). (Note:
  Panko 0.8.5's behavior is bifurcated — field-level filters apply `only` XOR `except`;
  attribute-level filters apply both sequentially. `Panko::CodeGen`'s uniform raise is
  stricter than either Panko path; Panko's own callers reach the engine through
  `Panko::FilterAdapter`, which flattens co-supplied `(only, except)` to a single key first,
  so they never trip it.)
- Names in `:only` / `:except` reference a value Field's **name** (the output key) but an
  **Association**'s **Source** (the declared relation) — so an aliased **Association** is
  addressed by the same key at the level and in its child filter, matching Panko 0.8.5.
  Child-filter keys reference the **Association**'s **Source** (which defaults to the
  **name** unless explicitly overridden).
- A key that does not match any node at its level is **ignored silently**. This keeps
  callers forward-compatible across **Descriptor** changes.
- Empty Hash `{}` at a level is equivalent to `nil` at that level — no filtering.
- Filters **do not inherit**: `:only` at the parent level does not propagate to child
  **Associations**. Children are governed by their own sub-hash (or are unfiltered if none
  is supplied).

### Interaction with Associations

- If an **Association**'s **Source** appears in `:except` at the parent level, the
  **Association** is dropped entirely — its nested **Generated Class** is not invoked.
- If an **Association**'s **Source** appears in `:only`, it is kept. Any child filter keyed
  by that same **Source** still applies inside the nested call.
- An **Association** not mentioned in `:only` / `:except` is included by default (subject
  to its own `if:` **Callable**).

## Filter before `if:`

When a **Filter** drops an **Association** (via `except:` at the parent, or by omission
from `only:`), the **Association**'s `if:` **Callable** is **not** evaluated. Filter
decisions short-circuit before `if:` runs. Rationale:

- `if:` is a **purity contract** (see [descriptor.md](descriptor.md)) — the library treats
  it as a predicate, not an observer. If the field is being dropped anyway, evaluating
  the predicate is wasted work.
- A filter-dropped **Association** should be **free**: no relation load, no callable
  dispatch. That's the point of `except:` on an expensive relation.

## Threading through Composition

The parent **Generated Class** scopes filters to the child's subtree at each nested call.
To avoid spraying nil-guards through the emitted code, `filters` is normalized at the
public entry point (`serialize_one` / `serialize_many`) into a **Filter object** via
`Panko::CodeGen::Filter.wrap(filters, FIELD_INDEX)` — either an **Indexed** wrapper around
the caller's Hash or the no-filter singleton. Downstream code always calls methods on that
object; it never branches on `filters.nil?`.

```ruby
# Shape of the normalized Filter interface (internal):
filter.drops?(2)                                          # => Boolean — is the Field at this FIELD_INDEX dropped?
filter.child(:author, AuthorSerializer_JSON::FIELD_INDEX) # => Filter — sub-filter for a nested Association's Source
```

`drops?` is keyed by the Field's **integer `FIELD_INDEX`** (each Generated Class carries a
frozen `FIELD_INDEX` constant assigning one index per Field at compile time), not by the
output name — so the hot path is one indexed lookup with no per-call symbol hashing. `child`
takes the nested Association's **Source** symbol plus the child class's own `FIELD_INDEX`
constant (the parent statically knows the child class, so it emits that constant token
directly).

At a nested call site the parent emits:

```ruby
# Inside PostSerializer_JSON#_write_one, for the :author has_one Association at FIELD_INDEX 2
# (the Source read + nil handling around the call are elided here — see generated-class.md):
unless filters.drops?(2)
  writer.push_key("author")
  @author_serializer._write_one(value, writer, context, scope,
                                filters.child(:author, AuthorSerializer_JSON::FIELD_INDEX))
end
```

No allocation on the parent side beyond what `child` returns. When the caller supplied no
filter, `child` returns the same no-filter singleton, so recursion stays allocation-free.

## No-filter fast path

The no-filter singleton (`Panko::CodeGen::Filter::None`) has trivial implementations:
`drops?` always returns `false`, `child` always returns itself.
These calls are prime YJIT inlining targets and the common case (caller passed no
`filters:`) incurs no Hash lookups, no Array scans, no allocations.

This singleton is the `Filter::None` module, frozen at module load. See
[§ Internal representation — the Indexed filter](#internal-representation--the-indexed-filter).

## JSON vs Hash output parity

Filter **semantics are identical** across both **Output Modes**. The code paths differ
only in how the surviving values are emitted (**Writer** push calls in JSON mode, Hash
literal population in Hash mode).

## Internal representation — the Indexed filter

The public `filters:` Hash shape and the Filter-object interface (`drops?`, `child`)
are the contract; the **implementation** behind them is the **Indexed** filter
(`lib/panko/code_gen/filters/indexed.rb`, with the no-filter singleton in
`lib/panko/code_gen/filters/none.rb`). `Filter.wrap` walks the caller's Hash once against
the Generated Class's `FIELD_INDEX` and picks one of two representations, chosen at
construction and never re-checked per call:

- **`Indexed::Bits`** — a single `Integer` bit-mask, used when the class has ≤ 63 Fields.
  `drops?(i)` is `Integer#[i]` — one bitwise extraction with no Bignum boxing on 64-bit
  Ruby (the 63 cutoff keeps the mask a tagged `Fixnum`).
- **`Indexed::Array`** — a Boolean `Array`, used for wider classes. `drops?(i)` is one
  indexed `Array#[]` load.

Both satisfy the same `drops?(<integer>)` / `child(<symbol>, <field_index>)`
contract as `Filter::None`, so emitted code stays monomorphic across the three shapes.

This "Indexed representation × single emit path" shape is the verdict of a benchmark
across the internal-representation × emit-strategy matrix.

## No compile-time disable knob

Filter support is a **default, unconditional feature** of every **Generated Class**. There
is no `Config` flag to switch it off — the no-filter case is already cheap via the
`Filter::None` singleton, and the filtered path costs one indexed `drops?` lookup per Field.
No caller-visible knob is warranted.
