# Filters

A **Filter** is a caller-supplied inclusion/exclusion rule applied to the **Descriptor**
tree at serialize time to prune fields or **Associations**. Filters are passed per call
(not baked into the **Generated Class**) and thread through **Composition**.

## Phase-1 behavior

Per [`goals.md` § Phasing](goals.md#phasing), filter support is implemented in phase 2
of the initial release. During phase 1, `serialize_one` / `serialize_many` accept the
`filters:` keyword in their signatures but **raise `NotImplementedError` on non-nil
values**.

Rationale: locking the public signature day 1 means Panko can integrate against
phase-1 builds without a later breaking change. Callers who do not pass `filters:`
work as intended; callers who do fail loudly, not silently.

Phase 2 replaces the `raise` with the implementation chosen by the experiment
described in [§ Experiment design](#experiment-design).

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
| `:only`                         | `Array<Symbol>`             | Allowlist. Only listed **Attribute** / **Method Attribute** / **Association** names emit. |
| `:except`                       | `Array<Symbol>`             | Denylist. Listed names are omitted. Everything else emits.                                |
| any other symbol                | `Hash` (same shape, nested) | Child filter for the **Association** whose **Source** matches the key.                    |

### Rules

- `:only` and `:except` at the same level are **mutually exclusive**. Supplying both is a
  caller error and raises `ArgumentError` at the first `_write_one` / `_to_hash` entry on
  that level. (Note: Panko 0.8.5's behavior is bifurcated — field-level filters apply
  `only` XOR `except`; attribute-level filters apply both sequentially. scg's uniform
  raise is stricter than either Panko path; the merge-time reconciliation is tracked in
  [`merging-into-panko-open-questions.md`](merging-into-panko-open-questions.md) § Q8.)
- Names in `:only` / `:except` reference the node's **name** (the output key), not its
  **Source**. Child-filter keys reference the **Association**'s **Source** (which defaults to
  the **name** unless explicitly overridden).
- A key that does not match any node at its level is **ignored silently**. This keeps
  callers forward-compatible across **Descriptor** changes.
- Empty Hash `{}` at a level is equivalent to `nil` at that level — no filtering.
- Filters **do not inherit**: `:only` at the parent level does not propagate to child
  **Associations**. Children are governed by their own sub-hash (or are unfiltered if none
  is supplied).

### Interaction with Associations

- If an **Association**'s name appears in `:except` at the parent level, the **Association**
  is dropped entirely — its nested **Generated Class** is not invoked.
- If an **Association**'s name appears in `:only`, it is kept. Any child filter keyed by
  that same **Source** still applies inside the nested call.
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
public entry point (`serialize_one` / `serialize_many`) into a **Filter object** — either
a wrapper around the caller's Hash or a singleton "no filter" value. Downstream code
always calls methods on that object; it never branches on `filters.nil?`.

```ruby
# Shape of the normalized Filter interface (internal):
filter.drops?(:comments)    # => Boolean — is this name filtered out?
filter.child(:comments)     # => Filter — sub-filter for a nested Association's Source
```

At a nested call site the parent emits:

```ruby
# Inside PostSerializer_JSON#_write_one, for the :comments Association:
unless filters.drops?(:comments)
  @comments_serializer._write_one(record.comments, writer, context, filters.child(:comments))
end
```

No allocation on the parent side beyond what `child` returns. When the caller supplied no
filter, `child` returns the same no-filter singleton, so recursion stays allocation-free.

## No-filter fast path

The no-filter singleton (`SerializersCodeGen::Filter::NONE` or equivalent) has trivial
implementations: `drops?` always returns `false`, `child` always returns itself. These
calls are prime YJIT inlining targets and the common case (caller passed no `filters:`)
incurs no Hash lookups, no Array scans, no allocations.

Whether this singleton is a dedicated class, a frozen empty Hash with method
extensions, or something else is an **internal representation** decision (see below).

## JSON vs Hash output parity

Filter **semantics are identical** across both **Output Modes**. The code paths differ
only in how the surviving values are emitted (**Writer** push calls in JSON mode, Hash
literal population in Hash mode).

## Internal representation — experiment-driven

The public `filters:` Hash shape and the internal Filter-object interface (`drops?`,
`child`) are locked. The **implementation** of that interface is not — and will be chosen
by benchmark. Candidates:

- **Option A — thin Hash wrapper.** The Filter object wraps the caller's Hash and answers
  `drops?` / `child` via direct Hash lookups + `Array#include?`. Zero walk cost up front,
  but `Array#include?` is O(n) per check.
- **Option B — pre-normalized index.** The top of `serialize_one` / `serialize_many`
  walks the Hash once and builds a compact index (per-level `Set`s keyed by node name,
  plus cached child Filter objects). `drops?` becomes O(1) `Set#include?`. Trades one
  walk + allocations per serialize call against many cheaper lookups.
- **Option C — the no-filter singleton.** Always used when the caller passes no filter.
  `drops?` returns `false`; `child` returns `self`. Constant, allocation-free, inlinable.
  Orthogonal to A vs B — it's the "nothing supplied" bypass either way.

The A-vs-B tradeoff hinges on how many field checks a typical serialization performs vs
the allocation cost of the index. Decided by **benchmark-ips** + **memory_profiler**
against representative fixtures before implementation. Either way, the public `filters:`
Hash shape does not change, and the no-filter singleton C stays as the common-case fast
path.

## No compile-time disable knob

Filter support is a **default, unconditional feature** of every **Generated Class**. There
is no `Config` flag to switch it off. The no-filter case is already cheap via the
Null-Object singleton; further optimization, if needed, goes through the dual-path
experiment below — not through a caller-visible knob.

## Dual-path emit — experiment-driven

An alternative to "one code path that always consults the Filter object" is to emit
**two specialized code paths** per **Generated Class**:

- `_write_one_unfiltered(record, writer, context)` — zero filter branches, zero Filter
  method calls. The optimal path when no filter is in effect.
- `_write_one_filtered(record, writer, context, filters)` — full filter-aware code.

`_write_one` becomes a tiny dispatcher:

```ruby
def _write_one(record, writer, context, filters)
  if filters.none?
    _write_one_unfiltered(record, writer, context)
  else
    _write_one_filtered(record, writer, context, filters)
  end
end
```

One branch per nested `_write_one` call (not per **Field**). At nested call sites, the
parent's filtered path invokes the child's `_write_one`, which re-dispatches: the moment
`filters.child(:assoc)` collapses to the no-filter singleton, the entire subtree below
runs on the unfiltered path.

**Tradeoff to measure**:

- **Pro**: the unfiltered path is genuinely optimal — no Filter interface calls at all,
  the smallest possible emitted body.
- **Con**: roughly 2× the method bodies per **Generated Class**. More source to emit,
  more to JIT-compile, more memory overhead per class. Unclear whether that cost shows
  up on real workloads.
- **Con**: doubles the snapshot surface for per-emitter-method tests.

Decided by **benchmark-ips** + **memory_profiler** against representative fixtures. The
public API is unaffected either way — dual-path is purely an internal emit strategy.

## Experiment design

The two implementation axes above (**Dual-path emit** and **Internal representation**)
are resolved together — they interact (Set-index cheapens the filter-aware path and
shrinks dual-path's benefit; Hash-wrapper does the opposite), so evaluating one under
an assumed default for the other risks a result that flips when the default flips.

The experiment runs in **phase 2** of the initial release, against the real codegen
output from phase 1 (not hand-written stubs). Phase 2 starts when
[`phase-1-bar.md`](phase-1-bar.md) is met.

### Matrix

**2×2 cells**: `{Hash-wrapper, Set-index}` × `{single-path, dual-path}`.

**5 fixtures × record-count sweep**:

| # | Descriptor shape          | Filter shape                  | Sizes          |
| - | ------------------------- | ----------------------------- | -------------- |
| 1 | wide-flat (~70 attrs)     | none                          | `[50, 2300]`   |
| 2 | wide-flat                 | shallow `:only` (20 of 70)    | `[1, 50, 2300]`|
| 3 | medium graph              | none                          | `[50, 2300]`   |
| 4 | medium graph              | shallow `:only` at top level  | `[1, 50, 2300]`|
| 5 | medium graph              | deep-nested (every level)     | `[1, 50, 2300]`|

**Medium graph** = entrypoint **Descriptor** with ~5 **Attributes** + 2 `has_one` + 1
`has_many` (~10 children). Matches the `graph` scenario sketched in
[`benchmarks.md`](benchmarks.md).

`size=1` is included on filter-present fixtures to observe Set-index's
normalization-amortization crossover (Set-index pays its upfront walk once per
`serialize_*` call; at size=1 that cost is undiluted, at size=2300 it's divided by
2300). `size=1` is omitted on `none` fixtures because no normalization happens when
`filters:` is nil.

**Reference row** per fixture/size: Filter-machinery-absent variant (identical to the
phase-1 body). Establishes the ceiling that any of the 4 cells is expected to approach.

### Decision rule — pre-registered

Committed to the experiment report header **before any numbers are recorded**. In
order:

1. **Pareto-dominance.** One cell ≥ every other cell on every fixture (within 5% noise)
   AND strictly better on at least one → pick it.
2. **Worst-fixture-row with 5% noise, on ips AND allocations.** Discard cells that
   are more than 5% worse than the best cell on any fixture in either metric; pick
   the survivor with the best worst-case ips.
3. **Simplicity tiebreak.** Prefer Hash-wrapper over Set-index; prefer single-path
   over dual-path. Complexity is a permanent tax; pick the boring cell when perf is
   a wash.

### Output mode coverage

Run in `:json` mode. Additionally, re-run one fixture (wide-flat × shallow) in
`:hash` mode to confirm the same cell wins — the **Filter** object is
output-mode-orthogonal, so any divergence is a signal to stop and investigate before
picking.

### Output artifacts

Follow the [`docs/research/`](research/) convention. Three files:

- `docs/research/filter_experiments_bench.rb` — harness + 4 Filter impls + per-fixture
  serializer stubs driven through the real compiled **Generated Class**.
- `docs/research/filter_experiments_results.md` — summary verdict at top, raw numbers,
  analysis, decision. Decision rule is pre-registered in the header before the bench
  runs.
- `docs/research/filter_experiments_yjit_output.txt` — raw stdout from the canonical
  run.

### Ruby and JIT target

Ruby 4.0.2 + YJIT. No-JIT numbers are secondary. Matches
[`docs/research/` conventions](research/README.md).
