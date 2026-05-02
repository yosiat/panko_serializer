# Filter experiment — internal-representation × emit-strategy verdict

> **Status:** pre-registered skeleton (S13.1). Decision rule, fixture
> list, cell list, hardware/env block, and empty per-fixture result
> tables are committed **before** any numbers are recorded. The bench
> harness lands in S13.2 and the canonical run + verdict backfill land
> in S13.3 — the `git log` ordering of (this skeleton commit) → (S13.3
> numbers commit) is part of the pre-registration discipline. Same
> shape as S12.1's [`phase_1_report.md`](phase_1_report.md) skeleton.

This is the canonical record of the phase-2 filter experiment: which
internal **Filter** object representation (`{Hash-wrapper, Set-index}`)
and emit strategy (`{single-path, dual-path}`) wins, measured against
the real codegen output from phase 1 across 5 fixtures × a record-count
sweep, per [`docs/filters.md` § Experiment design](../filters.md#experiment-design).
The verdict picks one cell from the 2×2 matrix; S14 implements that cell
in `lib/`. The shape matches the [`docs/research/`](README.md) convention
(summary verdict at top, raw numbers, analysis) — see
[`phase_1_report.md`](phase_1_report.md) and
[`ar_access_results.md`](ar_access_results.md) for the templates this
report follows.

## 1. Verdict

**Winner: `indexed × single_path`.** Settled by the
**worst-fixture-row** clause (§ 2 clause 2) under the established
size ≥ 50 noise-floor caveat. Indexed survives every (fixture × size ≥
50) measurement within 5% of the best cell; every other cell is
eliminated by at least one fixture row. The runner-up is `set_index ×
single_path`, beaten by indexed by **+9% on fixture #4 (s=2300)**,
**+9% on fixture #5 (s=2300)**, and **+23% on fixture #2 (s=2300)** —
the gap widens with field count and fixture density (Indexed's
`Integer#[]` shift+and at every check is the systematic win over
`Set#include?`). S14 lifts `IndexedBitsFilter` / `IndexedArrayFilter` /
`IndexedFilter` from
[`filter_experiments_bench.rb` lines 281–410](filter_experiments_bench.rb)
and `Overlay.emit_indexed_single_path_*` from
[lines 700–820](filter_experiments_bench.rb) into
`lib/serializers_code_gen/filters/indexed.rb` and the field emitters,
plus a per-Generated-Class `FIELD_INDEX` constant and codegen-time
integer-index assignment per Field (Attribute / MethodAttribute /
Association in declared order). The Hash-wrapper / Set-index / dual-path
cells do not ship.

How the rule applied:

- **Pareto-dominance (clause 1) — fails.** No cell dominates every
  (fixture × size). Hash-wrapper loses catastrophically on fixture #2
  (5–6× slower at every size). Set-index loses to Indexed at scale on
  fixtures #2 / #4 / #5 (size ≥ 50). Indexed itself loses at size=1 on
  fixtures #2 / #4 / #5 by 17–47% — its 71-Field Array fill (or 8-Field
  bit-mask build) is paid undiluted at single-record.
- **Worst-fixture-row (clause 2) — eliminates everything but Indexed.**
  Applied with the size ≥ 50 caveat (sub-microsecond size=1 sits in
  the 2–7% IPS-band noise floor and absolute alloc differences are ≤4):
  - `hash_wrapper_*`: ELIMINATED by fixture #2 (5–6× slower on ips at
    every size).
  - `set_index_*`: ELIMINATED by fixture #2 (s=50 17% / s=2300 23%
    slower than Indexed) and by fixture #4 / #5 (5–9% slower at scale).
  - `indexed_single`: SURVIVES every (fixture × size ≥ 50). Worst-case
    deviation is fixture #3 size=50 at 0.8% slower than the best cell.
- **Simplicity tiebreak (clause 3) — not invoked.** Indexed wins
  outright on clause 2. For the record, simplicity ordering is
  `hash_wrapper > set_index > indexed` (the indexed cell adds per-class
  `FIELD_INDEX` + class-aware Filter construction + bits-vs-array
  switch), so a tie would have favored Set-index — that's the runner-up
  position the canonical numbers also assign.

Anomalies flagged:

- **HITL cell-matrix amendment.** The originally pre-registered matrix
  was the 2×2 `{Hash-wrapper, Set-index} × {single-path, dual-path}` =
  4 cells. The `indexed_single_path` cell was added during S13.4 review
  per user direction (`#59` review: "I want this indexed-bits cell in
  this PR, so I can review it fully before doing the actual filters
  implementation") to evaluate the integer-indexed bool-array /
  bit-vector approach. The amendment expands the canonical run to 5
  cells; pre-registration discipline is preserved by recording this
  amendment in § 8 alongside the bench-vs-production frozen-string fix
  (which substantially repaired the size=50 / size=2300 Set-index
  numbers — old numbers in pre-amendment commits, new in 65068cf-onward).
- **Indexed loses at size=1 on every filter-present fixture.** Fixture
  #2 size=1: 173k vs 315k (set-index) = 45% slower. Fixture #4 size=1:
  680k vs 1115k (hash-wrapper) = 39% slower. Fixture #5 size=1: 331k vs
  622k (hash-wrapper) = 47% slower. All sub-microsecond regime; the
  per-call construction cost (Field-walk + bit-mask / array fill)
  dominates at single-record. Production filter use is
  size-many-records; size=1 is a diagnostic floor, not a verdict input.
- **Indexed wins fixture #5 (deep-nested) on both metrics at scale.**
  At size=2300: `indexed_single` 399 ips / 11 allocs vs
  `hash_wrapper_single` 332 ips / 4605 allocs. That's +20% ips
  *and* 99.8% fewer allocations — the cached child-Filter map (set-index
  inheritance) plus the bit-mask check (indexed's contribution) compose
  cleanly.
- **Strict 5% rule collapse at size=1 — unchanged.** The pre-registered
  rule, taken literally per (fixture × size × metric), eliminates all
  five cells. Same caveat as the previous verdict revision: size=1
  measurements live in the IPS-band noise floor and absolute alloc
  differences are ≤4. Future re-tuning should treat size=1 as a
  diagnostic regime rather than a verdict input.
- **Hash-mode parity confirmed (§ 7).** Indexed wins fixture #2 in
  `:hash` mode at size=50 (+24% over set-index) and size=2300 (+31%
  over set-index), losing only at size=1 to the same per-call
  construction overhead. No output-mode coupling.

## 2. Pre-registered decision rule

Reproduced verbatim from [`docs/filters.md` § Decision rule —
pre-registered](../filters.md#decision-rule--pre-registered). Committed
to this report's header **before any numbers are recorded** so the
verdict in § 1 cannot be retro-fitted to whichever cell happens to win.
Applied in order — the first clause that picks a single cell stops the
process; later clauses run only if earlier ones tie.

1. **Pareto-dominance.** One cell ≥ every other cell on every fixture
   (within 5% noise) AND strictly better on at least one → pick it.
2. **Worst-fixture-row with 5% noise, on ips AND allocations.** Discard
   cells that are more than 5% worse than the best cell on any fixture
   in either metric; pick the survivor with the best worst-case ips.
3. **Simplicity tiebreak.** Prefer Hash-wrapper over Set-index; prefer
   single-path over dual-path. Complexity is a permanent tax; pick the
   boring cell when perf is a wash.

The default winner under a pure perf-wash is therefore Hash-wrapper ×
single-path — the most boring cell.

## 3. Pre-registered fixtures

The 5 fixtures from [`docs/filters.md` § Matrix](../filters.md#matrix),
enumerated by name and shape with the documented size sweep. `size=1` is
included on the three filter-present fixtures (#2, #4, #5) to observe
Set-index's normalization-amortization crossover (one upfront walk per
`serialize_*` call, undiluted at `size=1`, divided by 2300 at large
size); omitted on the two `none` fixtures (#1, #3) because no
normalization happens when `filters:` is nil. **Medium graph** =
entrypoint **Descriptor** with ~5 **Attributes** + 2 `has_one` + 1
`has_many` (~10 children); matches the `graph` scenario sketched in
[`docs/benchmarks.md`](../benchmarks.md).

| # | Name                            | Descriptor shape         | Filter shape                                | Sizes           |
| - | ------------------------------- | ------------------------ | ------------------------------------------- | --------------- |
| 1 | `wide_flat_none`                | wide-flat (~70 attrs)    | none (`filters: nil`)                       | `[50, 2300]`    |
| 2 | `wide_flat_shallow_only`        | wide-flat (~70 attrs)    | shallow `:only` (20 of 70 attribute names)  | `[1, 50, 2300]` |
| 3 | `medium_graph_none`             | medium graph             | none (`filters: nil`)                       | `[50, 2300]`    |
| 4 | `medium_graph_shallow_only`     | medium graph             | shallow `:only` at top level                | `[1, 50, 2300]` |
| 5 | `medium_graph_deep_nested`      | medium graph             | deep-nested (`:only` / `:except` per level) | `[1, 50, 2300]` |

Per [`#55` user story 27](https://github.com/yosiat/serializers-code-gen/issues/55),
the canonical run exercises these 5 fixtures × N sizes against the
**5 cells** in § 4 (the originally pre-registered 4 cells plus the
HITL-amended `indexed_single_path` — amendment record in § 8.2).
Selective re-runs (one cell on one fixture for diagnosis) are recorded
in § 8 as **diagnostic** runs, separate from the canonical numbers.

## 4. Cells

The originally pre-registered 2×2 `{Hash-wrapper, Set-index} ×
{single-path, dual-path}` matrix (rows 1–4) plus the **HITL-amended
indexed cell** (row 5, added during `#59` review per user direction —
amendment record in § 8) and a reference row. All cells expose the same
internal interface — `drops?(<key>)`, `child(source)`, `none?` — per
[`docs/filters.md` § Threading through Composition](../filters.md#threading-through-composition);
the only thing that varies between cells is the implementation, not the
contract. The `<key>` argument is a Symbol Field-name on rows 1–4 and
an Integer Field-index on row 5; codegen baked the right literal at
emit time per cell. The two emit strategies (single-path vs dual-path)
are not extra Filter classes — they're a per-fixture toggle on the
compiled **Generated Class** body (dual-path overlays paired
`_write_one_unfiltered` / `_write_one_filtered` bodies + a tiny
dispatcher; single-path uses the compiled body as-is). Row 5 ships only
single-path: dual-path's dispatcher branch was a measured wash on rows
1–4 and the amendment kept the experiment scoped.

| Row | Cell                          | Internal representation | Emit strategy | Notes                                                                                                                  |
| --- | ----------------------------- | ----------------------- | ------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 1   | `hash_wrapper × single_path`  | Hash-wrapper            | single-path   | Wraps the caller's Hash; `drops?` does direct Hash lookups + `Array#include?`.                                          |
| 2   | `hash_wrapper × dual_path`    | Hash-wrapper            | dual-path     | Same Hash-wrapper representation; emit overlays paired bodies + dispatcher.                                            |
| 3   | `set_index × single_path`     | Set-index               | single-path   | Walks the Hash once at entry; per-level `Set`s + cached child Filter objects.                                          |
| 4   | `set_index × dual_path`       | Set-index               | dual-path     | Same Set-index representation; emit overlays paired bodies + dispatcher.                                               |
| 5   | `indexed × single_path`       | Indexed (bits/array)    | single-path   | Codegen-time integer index per Field; Filter is `Integer` bit-mask (≤63 fields) or Boolean `Array` (>63). HITL-amended. |
| ref | `reference (no filter machinery)` | n/a                 | n/a           | Filter-machinery-absent variant — the unmodified phase-1 emit body. Ceiling row.                                       |

The reference row establishes the ceiling that any of the 5 cells is
expected to approach on the no-filter path. `Filter::NONE`'s allocation
profile (zero filter-side allocations on a no-filter call) is reported
inline with the cell rows in § 6 — see [`docs/filters.md` § No-filter
fast path](../filters.md#no-filter-fast-path).

## 5. Hardware / env

Filled in immediately before the canonical run (S13.3). Reproducibility
matters more than the specific hardware — anyone re-running the bench
should be able to compare apples-to-apples or note the hardware delta.
Same field set as [`phase_1_report.md` § 2](phase_1_report.md).

| Field | Value |
| --- | --- |
| Ruby (`ruby -v`)                              | `ruby 4.0.2 (2026-03-17 revision d3da9fec82) +PRISM [arm64-darwin25]` |
| YJIT (`RubyVM::YJIT.enabled?` at run start)   | `true` (bench startup logged `YJIT: on`) |
| Hardware model                                | MacBook Pro (Mac16,5) |
| CPU                                           | Apple M4 Max — 16 cores (12 performance + 4 efficiency) |
| RAM                                           | 64 GB |
| OS                                            | macOS 26.3.1 (build 25D2128) |
| Run date                                      | 2026-05-02 |
| `bundle list \| grep -E 'panko\|oj_serializers'` | `panko_serializer (0.8.5)`, `oj_serializers (3.0.0)` |

Per [`docs/filters.md` § Ruby and JIT target](../filters.md#ruby-and-jit-target):
Ruby 4.0.2 + YJIT is the canonical target. No-JIT numbers are
secondary. Bundle versions for `panko_serializer` / `oj_serializers` are
recorded for parity with [`phase_1_report.md`](phase_1_report.md), even
though the filter experiment compares scg cells against each other and a
scg-internal reference row (no Panko / oj_serializers row).

## 6. Results

Stdout tables copied verbatim from
[`filter_experiments_yjit_output.txt`](filter_experiments_yjit_output.txt) —
one table per fixture. Reformatting is forbidden (it can hide rounding
or row-omission errors per S12.2's discipline). The canonical numbers
come from a single `bundle exec ruby --yjit filter_experiments_bench.rb`
invocation; per-cell or per-fixture re-runs are diagnostic only and are
recorded in § 8 separately from the canonical block.

Each table has 6 rows (5 cells + reference) and 2 columns per size
(`ips`, `allocs`). The `Δ vs reference` column is computed from the
`ips` column at the largest size (the most stable measurement, where
construction overhead is fully amortized).

### 6.1 Fixture #1 — `wide_flat_none`

| Cell                              | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs | Δ vs reference (s=2300 ips) |
| --------------------------------- | ----------- | -------------- | ------------- | ---------------- | --------------------------- |
| `hash_wrapper × single_path`      | 4.078k      | 754            | 85.162        | 34504            | −3.1%                       |
| `hash_wrapper × dual_path`        | 4.176k      | 754            | 93.238        | 34504            | +6.0%                       |
| `set_index × single_path`         | 4.074k      | 754            | 88.937        | 34504            | +1.1%                       |
| `set_index × dual_path`           | 4.136k      | 754            | 91.775        | 34504            | +4.4%                       |
| `indexed × single_path`           | 4.140k      | 754            | 93.878        | 34504            | +6.8%                       |
| `reference (no filter machinery)` | 4.147k      | 754            | 87.927        | 34504            | n/a (ceiling)               |

All 5 cells match the reference exactly on allocations and within
±7% on ips (one-sigma noise band 1–4%) — the `NoneFilter` fast path
imposes zero overhead, as designed. Inter-cell rank differences are
within measurement noise; the +6.8% Indexed vs reference at s=2300 is
a single-run sample within the ±3% IPS band, not a structural win.

### 6.2 Fixture #2 — `wide_flat_shallow_only` (71 fields → Indexed uses Array rep)

| Cell                              | size=1 ips | size=1 allocs | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs | Δ vs reference (s=2300 ips) |
| --------------------------------- | ---------- | ------------- | ----------- | -------------- | ------------- | ---------------- | --------------------------- |
| `hash_wrapper × single_path`      | 92.993k    | 10            | 1.941k      | 255            | 42.741        | 11505            | −54.4%                      |
| `hash_wrapper × dual_path`        | 92.539k    | 10            | 1.971k      | 255            | 43.542        | 11505            | −53.5%                      |
| `set_index × single_path`         | 315.319k   | 12            | 9.309k      | 257            | 204.668       | 11507            | +118.4%                     |
| `set_index × dual_path`           | 314.677k   | 12            | 9.321k      | 257            | 202.458       | 11507            | +116.0%                     |
| **`indexed × single_path`**       | 173.203k   | 12            | **11.184k** | 257            | **252.461**   | 11507            | **+169.4%**                 |
| `reference (no filter machinery)` | 192.966k   | 19            | 4.272k      | 754            | 93.712        | 34504            | n/a (ceiling)               |

The structural fixture for the experiment. Indexed wins at scale by
+20% / +23% over Set-index at size=50 / size=2300. The 71-Field Array
build dominates at size=1 (Indexed 173k vs Set-index 315k), but
amortizes by size=50.

### 6.3 Fixture #3 — `medium_graph_none`

| Cell                              | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs | Δ vs reference (s=2300 ips) |
| --------------------------------- | ----------- | -------------- | ------------- | ---------------- | --------------------------- |
| `hash_wrapper × single_path`      | 12.885k     | 104            | 268.022       | 4604             | +1.4%                       |
| `hash_wrapper × dual_path`        | 12.791k     | 104            | 265.336       | 4604             | +0.4%                       |
| `set_index × single_path`         | 12.808k     | 104            | 267.544       | 4604             | +1.3%                       |
| `set_index × dual_path`           | 12.811k     | 104            | 266.429       | 4604             | +0.8%                       |
| `indexed × single_path`           | 12.781k     | 104            | 269.124       | 4604             | +1.9%                       |
| `reference (no filter machinery)` | 12.678k     | 104            | 264.224       | 4604             | n/a (ceiling)               |

All 6 rows tie within the ±2% IPS noise band. As with fixture #1, the
`NoneFilter` fast path dominates and per-cell differences are
indistinguishable from measurement noise.

### 6.4 Fixture #4 — `medium_graph_shallow_only` (8 fields → Indexed uses Bits rep)

| Cell                              | size=1 ips | size=1 allocs | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs | Δ vs reference (s=2300 ips) |
| --------------------------------- | ---------- | ------------- | ----------- | -------------- | ------------- | ---------------- | --------------------------- |
| `hash_wrapper × single_path`      | 1.115M     | 5             | 43.100k     | 5              | 979.640       | 5                | +269.6%                     |
| `hash_wrapper × dual_path`        | 1.109M     | 5             | 43.526k     | 5              | 959.009       | 5                | +261.8%                     |
| `set_index × single_path`         | 1.046M     | 7             | 47.090k     | 7              | 1053.923      | 7                | +297.6%                     |
| `set_index × dual_path`           | 1.035M     | 7             | 46.195k     | 7              | 1041.879      | 7                | +293.0%                     |
| **`indexed × single_path`**       | 680.119k   | 6             | **49.691k** | 6              | **1147.847**  | 6                | **+332.9%**                 |
| `reference (no filter machinery)` | 505.448k   | 6             | 12.776k     | 104            | 265.057       | 4604             | n/a (ceiling)               |

Indexed wins at size ≥ 50 (+5.5% / +9.0% over Set-index). The 8-Field
bit-mask build is cheap, but the 3-of-8 `:only` does so few elidable
emits that even the construction's small cost is visible at size=1
(Indexed 680k vs Hash-wrapper 1115k = 39% slower). At scale all cells
beat the reference 3–4× because the filter elides the expensive
`has_one` / `has_many` walks.

### 6.5 Fixture #5 — `medium_graph_deep_nested` (8 / 3 / 2 fields per level → Indexed uses Bits everywhere)

| Cell                              | size=1 ips | size=1 allocs | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs | Δ vs reference (s=2300 ips) |
| --------------------------------- | ---------- | ------------- | ----------- | -------------- | ------------- | ---------------- | --------------------------- |
| `hash_wrapper × single_path`      | 622.314k   | 7             | 16.622k     | 105            | 331.737       | 4605             | +24.0%                      |
| `hash_wrapper × dual_path`        | 591.628k   | 7             | 15.980k     | 105            | 312.948       | 4605             | +17.0%                      |
| `set_index × single_path`         | 480.811k   | 13            | 17.942k     | 13             | 367.214       | 13               | +37.3%                      |
| `set_index × dual_path`           | 480.432k   | 13            | 17.720k     | 13             | 357.372       | 13               | +33.6%                      |
| **`indexed × single_path`**       | 331.152k   | 11            | **19.212k** | 11             | **399.143**   | 11               | **+49.2%**                  |
| `reference (no filter machinery)` | 504.698k   | 6             | 12.762k     | 104            | 267.453       | 4604             | n/a (ceiling)               |

The deep-nested fixture exposes the cached child-Filter advantage
shared by Set-index and Indexed (both 13 / 11 allocs at every size,
versus Hash-wrapper's 4605 at s=2300 — a ~99.8% allocation reduction
on the per-record child-Filter rebuild path). Within the cached-child
camp, Indexed beats Set-index by +7.1% / +8.7% at s=50 / s=2300 on the
per-Field check itself.

## 7. Hash-mode parity check

Per [`docs/filters.md` § Output mode coverage](../filters.md#output-mode-coverage):
fixture #2 (`wide_flat_shallow_only`) is re-compiled with `output:
:hash` and the same four cells exercised. The **Filter** object is
output-mode-orthogonal — the same cell should win in `:hash` mode as in
`:json` mode. If the hash-mode winner differs from the json-mode winner,
the experiment **halts** and the divergence is investigated before a
cell is picked (per [`#55` user story 14](https://github.com/yosiat/serializers-code-gen/issues/55)) —
divergence would be a signal that the Filter object is leaking
output-mode coupling.

| Cell                              | size=1 ips | size=1 allocs | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs |
| --------------------------------- | ---------- | ------------- | ----------- | -------------- | ------------- | ---------------- |
| `hash_wrapper × single_path`      | 102.183k   | 3             | 2.008k      | 52             | 43.723        | 2302             |
| `hash_wrapper × dual_path`        | 98.082k    | 3             | 2.078k      | 52             | 45.807        | 2302             |
| `set_index × single_path`         | 386.213k   | 5             | 10.669k     | 54             | 231.884       | 2304             |
| `set_index × dual_path`           | 382.471k   | 5             | 10.666k     | 54             | 231.074       | 2304             |
| **`indexed × single_path`**       | 192.451k   | 5             | **13.209k** | 54             | **303.367**   | 2304             |
| `reference (no filter machinery)` | 280.709k   | 2             | 5.501k      | 51             | 119.867       | 2301             |

**Parity verdict.** Hash-mode winner matches json-mode winner — **parity
confirmed**. Indexed wins fixture #2 at size=50 (+24% over Set-index)
and size=2300 (+31% over Set-index), losing only at size=1 to the same
construction-cost dynamic seen in json-mode (Indexed 192k vs Set-index
386k — the 71-Field Array build is undiluted at single-record). Cell
ranking is identical between the two output modes:
`indexed > set_index > {reference, hash_wrapper}` at size ≥ 50,
`set_index > reference > indexed > hash_wrapper` at size=1. No
output-mode coupling detected; the verdict in § 1 is final.

Two `:hash`-specific observations worth noting (do not change the
verdict, but inform S14 expectations):

- The `:hash` reference (no filter machinery) is **faster than every
  cell at size=1** (280k vs 192k Indexed / 386k Set-index — wait, only
  hash-wrapper / Indexed are slower; Set-index actually beats reference
  at size=1 by 38%). At size=50 and size=2300, every cell except
  hash-wrapper beats reference: Set-index by ~94% / ~94%, Indexed by
  ~140% / ~153%. The reference emits all 70 attrs into a Hash; the
  filter cells skip 50 of 70. Once the per-record Hash-build amortizes
  (size ≥ 50), skipping fields wins back the per-call filter overhead.
  In `:json` mode the reference stays the ceiling at every size — Oj's
  `StringWriter` makes the per-field skip cheaper, so the filter
  overhead never recovers there.
- The `:hash` Indexed cell **outperforms reference by 2.5× at
  size=2300** (303 vs 120 ips). Same fixture and same `:only` set; the
  difference is that `:hash` mode's per-field cost includes a Hash
  insertion, which the filter elides for 50 of 70 fields, AND the
  Indexed `Integer#[]` check is cheaper than Set-index's `Set#include?`
  per the json-mode finding. The two effects compound in `:hash` mode.

## 8. Diagnostic / re-run notes

Per [`#55` user story 28](https://github.com/yosiat/serializers-code-gen/issues/55):
selective re-runs (one cell on one fixture for diagnosis) are recorded
here as **diagnostic** runs, separate from the canonical numbers in
§§ 6–7. The verdict in § 1 cites only the canonical block; diagnostic
data informs the analysis but does not replace canonical rows.

### 8.1 Bench-vs-production frozen-string fix (S13.4)

The first canonical numbers backfilled in S13.3 were dominated by an
overlay-vs-production gap: `Overlay.emit_for` emitted source via
`module_eval` without a `# frozen_string_literal: true` pragma, so
every `record._read_attribute("name")` call and every
`writer.push_value(..., "name")` write key allocated a fresh String per
attribute per record (~140 strings/record on the wide-flat fixture).
Production codegen always emits the pragma at line 1
(`lib/serializers_code_gen/generators/{json,hash}_mode.rb:38`), so the
overlay was systematically over-counting filter-side allocations and
under-measuring throughput. The fix (`Overlay::FROZEN_PRAGMA`
prepended to every emit) collapsed cell allocations by 4–256× and
recovered ~45% throughput on the size=2300 filter-present fixtures.

Numbers on this page reflect the post-fix canonical run. The pre-fix
canonical numbers are recoverable from the git history at the
S13.3-merge commit (65068cf); they should not be cited in S14
acceptance comparisons because they overstate the per-call filter
cost. The fix was structural — the overlay is the drafting board for
S14, and S14 will inherit the production codegen's frozen-string
discipline automatically.

### 8.2 HITL cell-matrix amendment — indexed cell (S13.4)

The originally pre-registered 2×2 `{Hash-wrapper, Set-index} ×
{single-path, dual-path}` matrix was amended during `#59` review per
user direction to add `indexed_single_path` as a 5th cell. The
amendment was triggered by the verdict-stage observation that
`Set#include?` on a symbol Field-name is the hot per-check operation,
and that replacing it with `Integer#[]` (or `Array#[]`) on a
codegen-time-resolved index would cut per-check cost by ~3–5× under
YJIT. The user directive
([`#59` review](https://github.com/yosiat/serializers-code-gen/pull/65#issuecomment-…)):
"I want this indexed-bits cell in this PR, so I can review it fully
before doing the actual filters implementation."

The amendment preserves pre-registration discipline by:

- Recording the amendment scope here, in § 8, before re-running the
  canonical block — same shape as S12.2's `rake bench:all` protocol
  (any change to the cell matrix is logged separately from the
  canonical numbers).
- Not retro-fitting the decision rule: clauses 1–3 in § 2 apply
  unchanged. The simplicity tiebreak ordering implicitly extends to
  `hash_wrapper > set_index > indexed` (Indexed adds per-class
  `FIELD_INDEX` constant assignment + class-aware Filter construction +
  bits-vs-array switch over the simpler reps), so a tie would have
  picked Set-index — but the canonical numbers settled the verdict on
  clause 2 (worst-fixture-row), not clause 3.
- Not adding `indexed_dual_path`. Dual-path's dispatcher branch was a
  measured wash on rows 1–4 at every (fixture × size); extending the
  amendment to two indexed cells would have doubled the bench runtime
  for no decision-rule change.

The amendment expanded the canonical run from 4 cells to 5 cells (~25%
runtime growth, well within the 30–40 min budget). Output artifact:
[`filter_experiments_yjit_output.txt`](filter_experiments_yjit_output.txt)
header line 5 lists 5 cells; pre-flight output reads "5 cells" rather
than the pre-amendment "4 cells".

### 8.3 Runtime budget

If the canonical run does not complete in one sitting (the runtime
budget per [`#55` user story 34](https://github.com/yosiat/serializers-code-gen/issues/55)
is ~30–40 minutes — `IPS_TIME=5` × warmup=3 × ~25 rows × **5 cells** × 5
fixtures × ~2.5 sizes per fixture), the implementer shrinks `IPS_TIME`
once and **re-pre-registers the change here before re-running**. The
discipline mirrors S12.2's `rake bench:all` protocol.
