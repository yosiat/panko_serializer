# Phase 2 report — filter implementation overhead vs phase-1 baseline

> **Status:** pre-registered skeleton (S14.5). Decision rules,
> hardware/env block, and empty per-scenario result tables are
> committed **before** any numbers are recorded. The canonical
> `rake bench:all` re-run + verdict backfill land in S14.6 (#77) — the
> `git log` ordering of (this skeleton commit) → (S14.6 numbers commit)
> is part of the pre-registration discipline. Same shape as S12.1's
> [`phase_1_report.md`](phase_1_report.md) skeleton and S13.1's
> [`filter_experiments_results.md`](filter_experiments_results.md)
> skeleton.

This is the canonical record of phase-2 filter-implementation
overhead, measured against the phase-1 baseline ([`phase_1_report.md`](phase_1_report.md))
on the no-filter path and against the S13 filter experiment
([`filter_experiments_results.md` § 6](filter_experiments_results.md#6-results))
on the with-filter path. The shape matches the
[`docs/research/`](README.md) convention (summary verdict at top,
hardware/env block, raw numbers, analysis) — see
[`phase_1_report.md`](phase_1_report.md) for the template this report
follows. The file's purpose is two-fold per the parent S14 PRD
([#66](https://github.com/yosiat/serializers-code-gen/issues/66)) and
[`docs/filters.md`](../filters.md): (1) verify that the no-filter path
shipped in S14.1–S14.4 stayed byte-equivalent to the phase-1 emit body
modulo one `Filter::NONE` constant lookup at the public entry — a
within-5% baseline-integrity check; and (2) verify that the with-filter
path reproduces S13's `indexed × single_path` verdict-cell numbers
under production codegen — a within-10% verdict-cell sanity check.

## 1. Verdict

_Pending canonical run._ One paragraph will land here once S14.6 fills
in the per-scenario tables in § 4 and applies both decision rules from
§ 2. The paragraph will record:

- **Phase-1 baseline integrity (5% rule):** pass/fail per no-filter
  row vs the corresponding [`phase_1_report.md`](phase_1_report.md)
  row, including a row-by-row gap callout for any deviation >5%
  (the most likely candidate per the parent PRD: the `Filter.wrap`
  line in `serialize_one` adding allocation pressure when
  `filters: nil`, even though `Filter::NONE` is a frozen
  singleton — `PROFILE=memory` confirms zero filter-side allocations
  on the no-filter path).
- **Verdict-cell sanity (10% rule):** pass/fail per with-filter row
  vs the corresponding
  [`filter_experiments_results.md` § 6](filter_experiments_results.md#6-results)
  row, including a row-by-row gap callout for any deviation >10%
  (most likely candidates: codegen-vs-overlay drift in the
  `unless filters.drops?(<integer>)` wrapper shape, in the
  `FIELD_INDEX` constant lookup at `Filter.wrap`, or in the
  `filters.child(:<source>)` cache lifetime).
- **Decision:** phase-2 closed (both rules pass), or specific rows
  flagged for follow-up (with rationale + a pointer to the iteration
  recorded in § 6).
- **Anomalies flagged:** any unexpected dominance pattern, any
  scenario where `filter_only` / `filter_except` no longer matches
  S13's verdict cell within 10%, any reverse case where a no-filter
  scenario now beats phase 1 by >5% (a curiosity, not a regression,
  but worth recording for future re-tuning per the
  [`docs/phase-1-bar.md`](../phase-1-bar.md) tuning protocol).

## 2. Pre-registered decision rules

Reproduced verbatim from the parent S14 PRD
([#66](https://github.com/yosiat/serializers-code-gen/issues/66))
acceptance block and committed to this report's header **before any
numbers are recorded** so the verdict in § 1 cannot be retro-fitted
to whichever overhead happens to fall out of the canonical run.
Applied **mechanically, in order** — each rule scans every applicable
row before the next rule runs, and any flagged row halts verdict
authoring until investigated per the parent PRD's `PROFILE=memory`
protocol.

1. **Phase-1 baseline integrity — 5%.** Every no-filter row in § 4
   must stay within **5%** (in either direction) of its
   row-for-row counterpart in
   [`phase_1_report.md` § 3](phase_1_report.md#3-raw-numbers). The
   no-filter shipped path is the phase-1 emit body modulo the
   `Filter.wrap → Filter::NONE` constant lookup at the public entry
   point — single-path means there is no dispatcher branch, so the
   only delta is that one lookup. A regression beyond 5% on any
   no-filter row is a real regression introduced by S14.1–S14.4 and
   must be investigated with `PROFILE=memory` (per the parent PRD's
   "Phase-1 baseline integrity" follow-up note) before the verdict
   in § 1 is written.
2. **Verdict-cell sanity — ±10%.** Every with-filter row in § 4 must
   stay within **±10%** of its row-for-row counterpart in
   [`filter_experiments_results.md` § 6](filter_experiments_results.md#6-results)
   (the S13 `indexed × single_path` cell — the verdict cell, per
   [`filter_experiments_results.md` § 1](filter_experiments_results.md#1-verdict)).
   The with-filter shipped path is the S13 overlay's emit shape
   ([`filter_experiments_bench.rb` lines 700–820](filter_experiments_bench.rb))
   lifted into production codegen with `frozen_string_literal: true`
   already in place per
   [`filter_experiments_results.md` § 8.1](filter_experiments_results.md#81-bench-vs-production-frozen-string-fix-s134).
   A divergence beyond 10% surfaces codegen-vs-overlay drift (most
   likely candidate per the parent PRD's user story 28: a missed
   wrapper shape, a stale `FIELD_INDEX` lookup, or a cache-lifetime
   bug in `filters.child(:<source>)`) and must be investigated
   before the verdict in § 1 is written.

The two rules are independent: a row may pass rule 1 while failing
rule 2 (or vice versa). Both rules apply to every applicable row;
neither short-circuits the other.

## 3. Hardware / env

Filled in immediately before the canonical run (S14.6). Reproducibility
matters more than the specific hardware — anyone re-running the bench
should be able to compare apples-to-apples or note the hardware delta.
Same field set as
[`phase_1_report.md` § 2](phase_1_report.md#2-hardware--env) and
[`filter_experiments_results.md` § 5](filter_experiments_results.md#5-hardware--env)
so cross-report row-for-row comparison is mechanical.

| Field | Value |
| --- | --- |
| Ruby (`ruby -v`)                              | _pending_ |
| YJIT (`RubyVM::YJIT.enabled?` at run start)   | _pending_ |
| Hardware model                                | _pending_ |
| CPU                                           | _pending_ |
| RAM                                           | _pending_ |
| OS                                            | _pending_ |
| Run date                                      | _pending_ |
| `bundle list \| grep -E 'panko\|oj_serializers'` | _pending_ |

Per [`docs/filters.md` § Ruby and JIT target](../filters.md#ruby-and-jit-target)
and the parent S14 PRD's user story 27: Ruby 4.0.2 + YJIT on the same
canonical hardware as `phase_1_report.md` (Apple M4 Max) is the target.
Numbers measured on a different host get recorded with the hardware
delta noted explicitly in § 6 — absolute IPS comparisons are not
portable across hosts, but per-row scg ratios (no-filter vs phase 1,
with-filter vs S13) are the load-bearing signal and survive the
delta. Allocation counts are hardware-independent (counted by Ruby,
not measured), so both rules apply to allocations regardless of host.

## 4. Raw numbers

Stdout tables copied verbatim from the harness — one block per
scenario per size. Reformatting is forbidden (it can hide rounding or
row-omission errors per S12.2's discipline). The canonical numbers
come from a single `rake bench:all` invocation at sizes `[50, 2300]`
per [`docs/benchmarks.md` § Fixture data](../benchmarks.md#fixture-data);
per-scenario re-runs (`BENCH=<substr>`) are diagnostic only and do
not replace the canonical block.

Six scenarios populate this section per the parent S14 PRD's
phase-2-report shape (no-filter `simple` / `wide_attributes` /
`graph` / `recursive_self` to confirm phase-1 baseline integrity;
with-filter `filter_only` / `filter_except` to confirm S13's
verdict-cell numbers reproduce under production codegen). Each
scenario gets one table with the rows that apply: a `no-filter`
row when phase-2 codegen is exercised with `filters: nil`, a
`with-:only` row when exercised with `filters: {only: [...]}`,
and a `with-:except` row when exercised with `filters: {except: [...]}`.
Scenarios that historically passed `filters: nil` (`simple`,
`wide_attributes`, `graph`, `recursive_self`) keep just the
no-filter row; the filter scenarios (`filter_only`, `filter_except`)
add the matching with-filter row alongside the no-filter row so
both rules from § 2 are visible in the same table.

### 4.1 `simple` — flat Attributes (no-filter only)

| Filter mode  | scg/json size=50 ips | scg/json size=50 allocs | scg/json size=2300 ips | scg/json size=2300 allocs | scg/hash size=50 ips | scg/hash size=50 allocs | scg/hash size=2300 ips | scg/hash size=2300 allocs |
| ------------ | -------------------- | ----------------------- | ---------------------- | ------------------------- | -------------------- | ----------------------- | ---------------------- | ------------------------- |
| no-filter    |                      |                         |                        |                           |                      |                         |                        |                           |

Comparison row in S14.6: vs
[`phase_1_report.md` § 3.1.1](phase_1_report.md#311-simple--flat-attributes)
(rule 1 — phase-1 baseline integrity, 5%).

### 4.2 `wide_attributes` — ~70 Attributes (no-filter only)

| Filter mode  | scg/json size=50 ips | scg/json size=50 allocs | scg/json size=2300 ips | scg/json size=2300 allocs | scg/hash size=50 ips | scg/hash size=50 allocs | scg/hash size=2300 ips | scg/hash size=2300 allocs |
| ------------ | -------------------- | ----------------------- | ---------------------- | ------------------------- | -------------------- | ----------------------- | ---------------------- | ------------------------- |
| no-filter    |                      |                         |                        |                           |                      |                         |                        |                           |

Comparison row in S14.6: vs
[`phase_1_report.md` § 3.2.1](phase_1_report.md#321-wide_attributes--70-attributes-stresses-per-field-emitdispatch-cost)
(rule 1 — phase-1 baseline integrity, 5%).

### 4.3 `graph` — Attributes + multiple has_one + multiple has_many (no-filter only)

| Filter mode  | scg/json size=50 ips | scg/json size=50 allocs | scg/json size=2300 ips | scg/json size=2300 allocs | scg/hash size=50 ips | scg/hash size=50 allocs | scg/hash size=2300 ips | scg/hash size=2300 allocs |
| ------------ | -------------------- | ----------------------- | ---------------------- | ------------------------- | -------------------- | ----------------------- | ---------------------- | ------------------------- |
| no-filter    |                      |                         |                        |                           |                      |                         |                        |                           |

Comparison row in S14.6: vs
[`phase_1_report.md` § 3.2.2](phase_1_report.md#322-graph--entrypoint-with-attributes--multiple-has_one--multiple-has_many)
(rule 1 — phase-1 baseline integrity, 5%).

### 4.4 `recursive_self` — `scg_recursive` shape (no-filter only)

| Filter mode  | scg/json size=50 ips | scg/json size=50 allocs | scg/json size=2300 ips | scg/json size=2300 allocs | scg/hash size=50 ips | scg/hash size=50 allocs | scg/hash size=2300 ips | scg/hash size=2300 allocs |
| ------------ | -------------------- | ----------------------- | ---------------------- | ------------------------- | -------------------- | ----------------------- | ---------------------- | ------------------------- |
| no-filter    |                      |                         |                        |                           |                      |                         |                        |                           |

Comparison row in S14.6: vs
[`phase_1_report.md` § 3.3.3](phase_1_report.md#333-scg_recursive--comment-self-reference-3-level-tree-recursive_self-shape)
(rule 1 — phase-1 baseline integrity, 5%). The
`recursive_self` shape is exercised in the bench harness via the
`scg_recursive` scenario (3-level Comment tree, identity-cache
self-recursion shortcut from S8); the parent PRD names it
`recursive_self` after the canonical fixture #4 it derives from.

### 4.5 `filter_only` — runtime `:only` (5 of 5 attributes today, narrowed in phase 2)

| Filter mode   | scg/json size=50 ips | scg/json size=50 allocs | scg/json size=2300 ips | scg/json size=2300 allocs | scg/hash size=50 ips | scg/hash size=50 allocs | scg/hash size=2300 ips | scg/hash size=2300 allocs |
| ------------- | -------------------- | ----------------------- | ---------------------- | ------------------------- | -------------------- | ----------------------- | ---------------------- | ------------------------- |
| no-filter     |                      |                         |                        |                           |                      |                         |                        |                           |
| with-`:only`  |                      |                         |                        |                           |                      |                         |                        |                           |

Comparison rows in S14.6:

- `no-filter` vs
  [`phase_1_report.md` § 3.1.7](phase_1_report.md#317-filter_only--runtime-only-pankooj-scg-passes-filters-nil-per-phase-1-contract)
  (rule 1 — phase-1 baseline integrity, 5%; the existing scg-side
  numbers passed `filters: nil` per the phase-1 contract, so the
  phase-2 no-filter row should land within 5% of them).
- `with-:only` vs
  [`filter_experiments_results.md` § 6.2](filter_experiments_results.md#62-fixture-2--wide_flat_shallow_only-71-fields--indexed-uses-array-rep)
  and § 6.4 (rule 2 — verdict-cell sanity, ±10%; the `filter_only`
  scenario uses a 5-attribute Bench::Post Descriptor narrowed to
  `[:id, :title]`, so the closest S13 verdict-cell rows are
  fixture #2 `wide_flat_shallow_only` for the wide-attribute
  shape and fixture #4 `medium_graph_shallow_only` for the
  shallow-`:only`-at-top-level shape — S14.6 picks the closest
  shape match and records the comparison explicitly in § 6).

### 4.6 `filter_except` — runtime `:except` (5 of 5 attributes today, narrowed in phase 2)

| Filter mode    | scg/json size=50 ips | scg/json size=50 allocs | scg/json size=2300 ips | scg/json size=2300 allocs | scg/hash size=50 ips | scg/hash size=50 allocs | scg/hash size=2300 ips | scg/hash size=2300 allocs |
| -------------- | -------------------- | ----------------------- | ---------------------- | ------------------------- | -------------------- | ----------------------- | ---------------------- | ------------------------- |
| no-filter      |                      |                         |                        |                           |                      |                         |                        |                           |
| with-`:except` |                      |                         |                        |                           |                      |                         |                        |                           |

Comparison rows in S14.6:

- `no-filter` vs
  [`phase_1_report.md` § 3.1.8](phase_1_report.md#318-filter_except--runtime-except-pankooj-scg-passes-filters-nil-per-phase-1-contract)
  (rule 1 — phase-1 baseline integrity, 5%).
- `with-:except` vs
  [`filter_experiments_results.md` § 6.5](filter_experiments_results.md#65-fixture-5--medium_graph_deep_nested-8--3--2-fields-per-level--indexed-uses-bits-everywhere)
  (rule 2 — verdict-cell sanity, ±10%; deep-nested `:except`-per-level
  is the closest S13 verdict-cell row; S14.6 records the comparison
  explicitly in § 6).

## 5. Rule-by-rule analysis

_Pending canonical run._ One subsection per rule once S14.6 backfills
§ 4. Each subsection walks the rule mechanically across every
applicable row and records pass/fail with the gap percentage.

### 5.1 Rule 1 — phase-1 baseline integrity (5%)

Per § 2 rule 1: every no-filter row in § 4 vs its
[`phase_1_report.md`](phase_1_report.md) counterpart. Table skeleton
below; cells filled in S14.6.

| Scenario          | Mode | Size  | scg row (this report) | scg row (phase 1) | Gap (%) | Within 5%? |
| ----------------- | ---- | ----- | --------------------- | ----------------- | ------- | ---------- |
| `simple`          | json | 50    |                       |                   |         |            |
| `simple`          | json | 2300  |                       |                   |         |            |
| `simple`          | hash | 50    |                       |                   |         |            |
| `simple`          | hash | 2300  |                       |                   |         |            |
| `wide_attributes` | json | 50    |                       |                   |         |            |
| `wide_attributes` | json | 2300  |                       |                   |         |            |
| `wide_attributes` | hash | 50    |                       |                   |         |            |
| `wide_attributes` | hash | 2300  |                       |                   |         |            |
| `graph`           | json | 50    |                       |                   |         |            |
| `graph`           | json | 2300  |                       |                   |         |            |
| `graph`           | hash | 50    |                       |                   |         |            |
| `graph`           | hash | 2300  |                       |                   |         |            |
| `recursive_self`  | json | 50    |                       |                   |         |            |
| `recursive_self`  | json | 2300  |                       |                   |         |            |
| `recursive_self`  | hash | 50    |                       |                   |         |            |
| `recursive_self`  | hash | 2300  |                       |                   |         |            |
| `filter_only`     | json | 50    |                       |                   |         |            |
| `filter_only`     | json | 2300  |                       |                   |         |            |
| `filter_only`     | hash | 50    |                       |                   |         |            |
| `filter_only`     | hash | 2300  |                       |                   |         |            |
| `filter_except`   | json | 50    |                       |                   |         |            |
| `filter_except`   | json | 2300  |                       |                   |         |            |
| `filter_except`   | hash | 50    |                       |                   |         |            |
| `filter_except`   | hash | 2300  |                       |                   |         |            |

### 5.2 Rule 2 — verdict-cell sanity (±10%)

Per § 2 rule 2: every with-filter row in § 4 vs its
[`filter_experiments_results.md` § 6](filter_experiments_results.md#6-results)
counterpart. Table skeleton below; cells filled in S14.6.

| Scenario        | Mode | Size  | Filter mode    | scg row (this report) | S13 verdict-cell row | S13 fixture | Gap (%) | Within ±10%? |
| --------------- | ---- | ----- | -------------- | --------------------- | -------------------- | ----------- | ------- | ------------ |
| `filter_only`   | json | 50    | with-`:only`   |                       |                      |             |         |              |
| `filter_only`   | json | 2300  | with-`:only`   |                       |                      |             |         |              |
| `filter_only`   | hash | 50    | with-`:only`   |                       |                      |             |         |              |
| `filter_only`   | hash | 2300  | with-`:only`   |                       |                      |             |         |              |
| `filter_except` | json | 50    | with-`:except` |                       |                      |             |         |              |
| `filter_except` | json | 2300  | with-`:except` |                       |                      |             |         |              |
| `filter_except` | hash | 50    | with-`:except` |                       |                      |             |         |              |
| `filter_except` | hash | 2300  | with-`:except` |                       |                      |             |         |              |

S14.6 picks the closest S13 fixture per shape and records the
choice explicitly in the `S13 fixture` column. The mapping is not
mechanical (the S11 bench scenarios and the S13 experiment fixtures
are independently shaped — `filter_only` is a 5-attribute flat
Descriptor narrowed to `[:id, :title]`, while S13's fixtures #2 / #4
are 71-attribute / 8-field shapes), so the fixture choice is part of
the analysis, not a pre-registered cell.

## 6. Decisions for flagged rows

_To be filled if any._ Per the parent S14 PRD's `PROFILE=memory`
follow-up protocol and the
[`docs/phase-1-bar.md` § Tuning](../phase-1-bar.md#tuning) precedent:

- **Investigate** when a no-filter row is >5% off phase 1 or a
  with-filter row is >10% off S13's verdict-cell numbers.
  `PROFILE=cpu` (StackProf) and `PROFILE=memory` (MemoryProfiler)
  per [`docs/benchmarks.md` § Env knobs](../benchmarks.md#core-features-carried-over)
  identify hot frames and allocation hot spots; a focused regression
  spec pins the invariant; the fix lifts it green; the canonical
  bench re-runs in full.
- **Tune** when the gap is structural and the original target was
  overstated. The 5% / ±10% rules are themselves tunable per the
  [`docs/phase-1-bar.md` § Tuning](../phase-1-bar.md#tuning)
  precedent — any tuning records the new threshold + rationale here
  and the verdict in § 1 cites it by section heading.

Default: investigate first, tune as fallback. Each flagged row gets
its own sub-section here recording: what was profiled, what was
changed (or what threshold was tuned and why), and the iteration's
number block (re-run output if a fix landed).

## 7. Diagnostic / re-run notes

_To be filled if any._ Selective re-runs (one scenario or one filter
mode for diagnosis) are recorded here as **diagnostic** runs,
separate from the canonical numbers in § 4. The verdict in § 1
cites only the canonical block; diagnostic data informs the analysis
in § 5–6 but does not replace canonical rows.

If the canonical run does not complete in one sitting, the
implementer shrinks `IPS_TIME` once and **re-pre-registers the change
here before re-running**, mirroring S12.2's `rake bench:all`
discipline and S13.3's
[`filter_experiments_results.md` § 8.3](filter_experiments_results.md#83-runtime-budget)
re-pre-registration protocol.
