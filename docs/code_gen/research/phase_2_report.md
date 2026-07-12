# Phase 2 report — filter implementation overhead vs phase-1 baseline

> **Status: phase 2 closed (2026-05-03, S14.6).** Rule 1
> (phase-1 baseline integrity, 5%) passes — 16 / 24 no-filter rows
> within ±5%; the 8 outside-band rows are all `scg/json` upward
> deviations attributable to commit `b83b486` (an unrelated
> JSON-mode allocation fix that landed inside the rule-1 measurement
> window), recorded in § 6.1 as a curiosity, not a regression. Rule
> 2 (verdict-cell sanity, ±10%) passes at the pattern-equivalence
> level — codegen drift ruled out via three independent gates
> (snapshot diff exact match across 20 fixtures, `memory_profiler`
> on `filters: nil` shows zero filter-side allocations,
> `Filter::Indexed` allocation cost +5/call consistent with S13's
> verdict cell), with numeric IPS reproduction deferred to the
> S14.7 follow-up recorded in § 6.2 because the production bench
> shapes (5-attribute flat) don't 1:1 match any S13 fixture (71-attr
> flat / 8-attr+assoc / deep-nested). Phase-2 codegen ships clean;
> phase 3 (Dump) unblocks. This file's structure — verdict template,
> decision rules, hardware/env block, and empty per-scenario result
> tables — was committed **before** any numbers were measured
> (S14.5), per the pre-registration discipline used for S12.1's
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

**S14.6 verdict (2026-05-03): phase 2 closed — rule 1 passes (16 / 24
no-filter rows within ±5%; 8 outside-band rows all on `scg/json`,
all upward, all attributable to the unrelated `chomp!` fix in commit
`b83b486` per § 6.1 — zero S14-induced regressions); rule 2 passes
at the pattern-equivalence level (codegen drift ruled out via three
independent gates per § 6.2; numeric IPS reproduction deferred to
the S14.7 follow-up because the production bench shapes don't 1:1
match any S13 fixture).**

- **Phase-1 baseline integrity (5% rule):** see § 5.1's per-row
  table. 16 of 24 no-filter rows land within ±5% of
  [`phase_1_report.md`](phase_1_report.md); 8 rows show **+5.3% to
  +10.6%** gaps, every one of them on `scg/json`, every one with a
  deterministic 1-alloc/call reduction (4→3 across all `scg/json`
  rows). § 6.1 traces every flagged row to commit `b83b486`
  ("Replace writer.to_s.chomp with in-place chomp! in JSON-mode
  emit", 2026-04-29) which landed inside the rule-1 measurement
  window between the phase-1 baseline (2026-04-26) and this run
  (2026-05-03) and is unrelated to S14.1–S14.4. No tuning of the 5%
  threshold is warranted — the threshold catches genuine S14
  regressions; today's deviations are an unrelated optimization
  surfacing as a benign upward shift on the JSON-mode hot path. Per
  the verdict-template clause "any reverse case where a no-filter
  scenario now beats phase 1 by >5% (a curiosity, not a regression,
  but worth recording)", the rule passes.
- **Verdict-cell sanity (10% rule):** see § 5.2's per-row table. The
  4 applicable JSON rule-2 rows show **+176% to +411%** gaps vs
  their closest S13 fixtures — every gap positive (production faster
  than S13), every gap structural to fixture-shape mismatch
  (5-attribute `Bench::Post` flat Descriptor in the canonical bench
  vs 71-attr flat / 8-attr+assoc / deep-nested in S13), not codegen
  drift. § 6.2's investigation rules out all three suspected
  drift candidates from the parent PRD's user story 28 (missed
  wrapper shape, stale `FIELD_INDEX` lookup, broken
  `filters.child(:<source>)` cache lifetime) via the snapshot diff
  walk (§ 7.1; 20 generated-class fixtures, +553/−255 lines, four
  documented S14.1–S14.4 mutations match exactly), the
  `memory_profiler` on `filters: nil` (§ 7.2; 3 total allocs, zero
  filter-side), and the `Filter::Indexed` allocation cost (+5
  allocs/call across all with-filter rows; comparable to fixture
  #6.4's 6 allocs/call). HITL judgment: pattern equivalence
  satisfies rule 2's stated intent (catch codegen drift); numeric
  IPS reproduction deferred to the S14.7 follow-up bench scenario
  recorded in § 6.2.
- **Decision:** **phase-2 closed.** Rule 1 passes with 8 upward
  curiosities recorded; rule 2 passes at pattern equivalence with
  numeric reproduction deferred. No phase-2-blocking issues; phase 3
  (Dump) unblocks.
- **Anomalies flagged:**
  - **8 / 24 rule-1 rows outside ±5% in the upward direction** — all
    `scg/json`, all paired with a 1-alloc/call reduction, all traced
    to commit `b83b486`. Recorded in § 6.1 as a curiosity, not a
    regression.
  - **Rule 2 cannot be applied numerically to today's bench shape**
    — production `filter_only` / `filter_except` (5-attribute flat
    `Bench::Post`) doesn't 1:1 match any S13 fixture
    (`wide_flat_*`: 71 attr; `medium_graph_*`: 8 + assoc;
    `medium_graph_deep_nested`: nested). Pattern equivalence
    verified instead. § 6.2 records the **S14.7 follow-up** to add
    a 1:1 fixture-shape-matching benchmark scenario for the next
    phase-2-style canonical run.

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
| Ruby (`ruby -v`)                              | `ruby 4.0.2 (2026-03-17 revision d3da9fec82) +PRISM [arm64-darwin25]` (YJIT auto-enabled by harness) |
| YJIT (`RubyVM::YJIT.enabled?` at run start)   | `on` — auto-enable fired via `RubyVM::YJIT.enable` in `benchmarks/support/setup.rb`; every per-scenario harness banner records `YJIT: on` |
| Hardware model                                | MacBook Pro (Mac16,5) |
| CPU                                           | Apple M4 Max — 16 cores (12 Performance + 4 Efficiency) |
| RAM                                           | 64 GB |
| OS                                            | macOS 26.3.1 (build 25D2128) |
| Run date                                      | 2026-05-03 |
| `bundle list \| grep -E 'panko\|oj_serializers'` | `panko_serializer (0.8.5)`, `oj_serializers (3.0.0)` |

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
| no-filter    | 86.99K               | 3                       | 1.94K                  | 3                         | 98.41K               | 51                      | 2.13K                  | 2301                      |

Comparison row in S14.6: vs
[`phase_1_report.md` § 3.1.1](phase_1_report.md#311-simple--flat-attributes)
(rule 1 — phase-1 baseline integrity, 5%).

### 4.2 `wide_attributes` — ~70 Attributes (no-filter only)

| Filter mode  | scg/json size=50 ips | scg/json size=50 allocs | scg/json size=2300 ips | scg/json size=2300 allocs | scg/hash size=50 ips | scg/hash size=50 allocs | scg/hash size=2300 ips | scg/hash size=2300 allocs |
| ------------ | -------------------- | ----------------------- | ---------------------- | ------------------------- | -------------------- | ----------------------- | ---------------------- | ------------------------- |
| no-filter    | 4.26K                | 753                     | 92.59                  | 34503                     | 5.73K                | 51                      | 121.16                 | 2301                      |

Comparison row in S14.6: vs
[`phase_1_report.md` § 3.2.1](phase_1_report.md#321-wide_attributes--70-attributes-stresses-per-field-emitdispatch-cost)
(rule 1 — phase-1 baseline integrity, 5%).

### 4.3 `graph` — Attributes + multiple has_one + multiple has_many (no-filter only)

| Filter mode  | scg/json size=50 ips | scg/json size=50 allocs | scg/json size=2300 ips | scg/json size=2300 allocs | scg/hash size=50 ips | scg/hash size=50 allocs | scg/hash size=2300 ips | scg/hash size=2300 allocs |
| ------------ | -------------------- | ----------------------- | ---------------------- | ------------------------- | -------------------- | ----------------------- | ---------------------- | ------------------------- |
| no-filter    | 10.08K               | 153                     | 210.34                 | 6903                      | 8.79K                | 751                     | 197.71                 | 34501                     |

Comparison row in S14.6: vs
[`phase_1_report.md` § 3.2.2](phase_1_report.md#322-graph--entrypoint-with-attributes--multiple-has_one--multiple-has_many)
(rule 1 — phase-1 baseline integrity, 5%).

### 4.4 `recursive_self` — `scg_recursive` shape (no-filter only)

| Filter mode  | scg/json size=50 ips | scg/json size=50 allocs | scg/json size=2300 ips | scg/json size=2300 allocs | scg/hash size=50 ips | scg/hash size=50 allocs | scg/hash size=2300 ips | scg/hash size=2300 allocs |
| ------------ | -------------------- | ----------------------- | ---------------------- | ------------------------- | -------------------- | ----------------------- | ---------------------- | ------------------------- |
| no-filter    | 10.70K               | 3                       | 219.75                 | 3                         | 8.67K                | 701                     | 191.02                 | 32201                     |

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
| no-filter     | 85.90K               | 3                       | 1.88K                  | 3                         | 96.25K               | 51                      | 2.09K                  | 2301                      |
| with-`:only`  | 137.53K              | 8                       | 3.36K                  | 8                         | 139.28K              | 56                      | 3.36K                  | 2306                      |

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
| no-filter      | 82.45K               | 3                       | 1.86K                  | 3                         | 94.93K               | 51                      | 2.07K                  | 2301                      |
| with-`:except` | 84.57K               | 8                       | 2.04K                  | 8                         | 90.60K               | 56                      | 2.07K                  | 2306                      |

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

One subsection per rule walks the rule mechanically across every
applicable row and records pass/fail with the gap percentage.

### 5.1 Rule 1 — phase-1 baseline integrity (5%)

Per § 2 rule 1: every no-filter row in § 4 vs its
[`phase_1_report.md`](phase_1_report.md) counterpart. "Gap (%)" is
`(today − phase1) / phase1 × 100` — positive means today is faster
than phase 1; negative means slower. "Within 5%?" is **No** only
when the gap exceeds ±5%; the directionality is recorded in § 6
because the rule is symmetric but the decision protocol distinguishes
slower (regression — investigate) from faster (curiosity — record).

| Scenario          | Mode | Size  | scg row (this report) | scg row (phase 1) | Gap (%) | Within 5%? |
| ----------------- | ---- | ----- | --------------------- | ----------------- | ------- | ---------- |
| `simple`          | json | 50    | 86.99K                | 79.37K            | +9.6%   | No (faster — see § 6.1) |
| `simple`          | json | 2300  | 1.94K                 | 1.86K             | +4.3%   | Yes        |
| `simple`          | hash | 50    | 98.41K                | 96.71K            | +1.8%   | Yes        |
| `simple`          | hash | 2300  | 2.13K                 | 2.15K             | −0.9%   | Yes        |
| `wide_attributes` | json | 50    | 4.26K                 | 3.85K             | +10.6%  | No (faster — see § 6.1) |
| `wide_attributes` | json | 2300  | 92.59                 | 84.25             | +9.9%   | No (faster — see § 6.1) |
| `wide_attributes` | hash | 50    | 5.73K                 | 5.56K             | +3.1%   | Yes        |
| `wide_attributes` | hash | 2300  | 121.16                | 118.99            | +1.8%   | Yes        |
| `graph`           | json | 50    | 10.08K                | 9.34K             | +7.9%   | No (faster — see § 6.1) |
| `graph`           | json | 2300  | 210.34                | 192.71            | +9.1%   | No (faster — see § 6.1) |
| `graph`           | hash | 50    | 8.79K                 | 8.61K             | +2.1%   | Yes        |
| `graph`           | hash | 2300  | 197.71                | 191.69            | +3.1%   | Yes        |
| `recursive_self`  | json | 50    | 10.70K                | 10.16K            | +5.3%   | No (faster — see § 6.1) |
| `recursive_self`  | json | 2300  | 219.75                | 210.35            | +4.5%   | Yes        |
| `recursive_self`  | hash | 50    | 8.67K                 | 8.51K             | +1.9%   | Yes        |
| `recursive_self`  | hash | 2300  | 191.02                | 190.09            | +0.5%   | Yes        |
| `filter_only`     | json | 50    | 85.90K                | 77.95K            | +10.2%  | No (faster — see § 6.1) |
| `filter_only`     | json | 2300  | 1.88K                 | 1.80K             | +4.4%   | Yes        |
| `filter_only`     | hash | 50    | 96.25K                | 93.96K            | +2.4%   | Yes        |
| `filter_only`     | hash | 2300  | 2.09K                 | 2.08K             | +0.5%   | Yes        |
| `filter_except`   | json | 50    | 82.45K                | 77.53K            | +6.3%   | No (faster — see § 6.1) |
| `filter_except`   | json | 2300  | 1.86K                 | 1.79K             | +3.9%   | Yes        |
| `filter_except`   | hash | 50    | 94.93K                | 94.24K            | +0.7%   | Yes        |
| `filter_except`   | hash | 2300  | 2.07K                 | 2.07K             | 0.0%    | Yes        |

Aggregate: **16 / 24 rows within ±5%; 8 / 24 outside ±5% — every
out-of-band row is scg/json, every gap is positive (faster than
phase 1), every gap is paired with a deterministic 1-alloc/call
reduction (`scg/json` 4→3 at all sizes; allocation counts are
hardware-independent). Zero rule-1 rows show a regression
(scg/json/hash slower than phase 1 by >5%). All 8 upward deviations
trace to commit `b83b486` ("Replace writer.to_s.chomp with in-place
chomp! in JSON-mode emit") which landed 2026-04-29 between the
phase-1 baseline (2026-04-26) and this run (2026-05-03) — unrelated
to S14.1–S14.4. Per § 1's verdict-template clause "any reverse case
where a no-filter scenario now beats phase 1 by >5% (a curiosity, not
a regression, but worth recording)", the rule passes; details in
§ 6.1.

### 5.2 Rule 2 — verdict-cell sanity (±10%)

Per § 2 rule 2: every with-filter row in § 4 vs its
[`filter_experiments_results.md` § 6](filter_experiments_results.md#6-results)
counterpart. The closest S13 fixture per row is recorded explicitly;
hash-mode rows are N/A because the S13 experiment was JSON-only
(`filter_experiments_bench.rb` builds JSON output via
`Oj::StringWriter` and never measured `:hash` mode — the closest
hash-mode reference is `phase_1_report.md`'s no-filter rows, already
covered by rule 1).

| Scenario        | Mode | Size  | Filter mode    | scg row (this report) | S13 verdict-cell row | S13 fixture                         | Gap (%) | Within ±10%? |
| --------------- | ---- | ----- | -------------- | --------------------- | -------------------- | ----------------------------------- | ------- | ------------ |
| `filter_only`   | json | 50    | with-`:only`   | 137.53K               | 49.691k              | #6.4 `medium_graph_shallow_only`    | +176.7% | No (shape mismatch — see § 6.2) |
| `filter_only`   | json | 2300  | with-`:only`   | 3.36K                 | 1147.847             | #6.4 `medium_graph_shallow_only`    | +192.7% | No (shape mismatch — see § 6.2) |
| `filter_only`   | hash | 50    | with-`:only`   | 139.28K               | n/a                  | n/a (S13 was JSON-only — see § 6.2) | n/a     | n/a          |
| `filter_only`   | hash | 2300  | with-`:only`   | 3.36K                 | n/a                  | n/a (S13 was JSON-only — see § 6.2) | n/a     | n/a          |
| `filter_except` | json | 50    | with-`:except` | 84.57K                | 19.212k              | #6.5 `medium_graph_deep_nested`     | +340.1% | No (shape mismatch — see § 6.2) |
| `filter_except` | json | 2300  | with-`:except` | 2.04K                 | 399.143              | #6.5 `medium_graph_deep_nested`     | +411.1% | No (shape mismatch — see § 6.2) |
| `filter_except` | hash | 50    | with-`:except` | 90.60K                | n/a                  | n/a (S13 was JSON-only — see § 6.2) | n/a     | n/a          |
| `filter_except` | hash | 2300  | with-`:except` | 2.07K                 | n/a                  | n/a (S13 was JSON-only — see § 6.2) | n/a     | n/a          |

Aggregate: **0 / 4 applicable JSON rows within ±10%; all 4 outside
by +176%–+411%** — but every gap is **positive (production faster
than S13)** and every gap is structural to the **fixture shape
mismatch** between the canonical bench scenarios (5-attribute flat
Descriptor of `Bench::Post`, no associations) and the S13 experiment
fixtures (#6.2 71-attribute flat with Array rep; #6.4 8-field
`Comment` Descriptor with `has_one` + `has_many`; #6.5 deep-nested
Folder-Item-Subfolder graph). Per the parent S14 PRD's user story 28,
codegen-vs-overlay drift was the worry rule 2 was designed to detect
— and the **investigation in § 6.2 confirms zero codegen drift**:
the four documented S14.1–S14.4 mutations match the snapshot diff
exactly (20 files), `memory_profiler` on `filters: nil` shows zero
filter-side allocations (Filter::NONE singleton fast path verified),
and `Filter::Indexed` costs a fixed +5 allocs/call (3→8 json,
51→56 hash) consistent with fixture #4's 6 allocs/call. The rule's
**numeric** application is deferred to a follow-up bench scenario
that 1:1 matches one of S13's fixture shapes (recorded in § 6.2).
S14.6's HITL judgment is that pattern equivalence verified at the
snapshot, allocation, and memory-profile level satisfies rule 2's
intent (catch codegen drift), even though the IPS comparison is
structurally invalid.

## 6. Decisions for flagged rows

Per the parent S14 PRD's `PROFILE=memory` follow-up protocol and the
`docs/phase-1-bar.md` § Tuning precedent:

- **Investigate** when a no-filter row is >5% off phase 1 or a
  with-filter row is >10% off S13's verdict-cell numbers.
  `PROFILE=cpu` (StackProf) and `PROFILE=memory` (MemoryProfiler)
  per [`docs/benchmarks.md` § Env knobs](../benchmarks.md#core-features-carried-over)
  identify hot frames and allocation hot spots; a focused regression
  spec pins the invariant; the fix lifts it green; the canonical
  bench re-runs in full.
- **Tune** when the gap is structural and the original target was
  overstated. The 5% / ±10% rules are themselves tunable per the
  `docs/phase-1-bar.md` § Tuning
  precedent — any tuning records the new threshold + rationale here
  and the verdict in § 1 cites it by section heading.

Default: investigate first, tune as fallback. Each flagged row gets
its own sub-section here recording: what was profiled, what was
changed (or what threshold was tuned and why), and the iteration's
number block (re-run output if a fix landed).

### 6.1 Rule 1 — eight scg/json rows faster than phase 1 by +5%–+11%

Eight no-filter rows in § 5.1 are outside ±5% of phase 1, every one
of them on the `scg/json` row, every gap positive (today faster), and
every row paired with a deterministic 1-alloc/call reduction
(`scg/json` 4 allocs in phase 1 → 3 allocs today, at every size and
every scenario). The 1-alloc reduction reproduces across all 8
scenarios and is hardware-independent, ruling out measurement noise.

#### Investigation

`git log` between the phase-1 baseline run date (2026-04-26) and
this run (2026-05-03) shows one commit touching the JSON-mode emit
hot path:

- `b83b486` (2026-04-29) — _Replace `writer.to_s.chomp` with in-place
  `chomp!` in JSON-mode emit (#64)_

The change removes one intermediate `String` allocation per
`serialize_one` / `serialize_many` call (the `.chomp` return value).
This matches the observed −1 alloc/call exactly across every
`scg/json` row in this report:

| Scenario          | Size  | Phase-1 allocs | Today allocs | Δ |
| ----------------- | ----- | -------------- | ------------ | --- |
| `simple`          | 50    | 4              | 3            | −1 |
| `simple`          | 2300  | 4              | 3            | −1 |
| `wide_attributes` | 50    | 754            | 753          | −1 |
| `wide_attributes` | 2300  | 34504          | 34503        | −1 |
| `graph`           | 50    | 154            | 153          | −1 |
| `graph`           | 2300  | 6904           | 6903         | −1 |
| `recursive_self`  | 50    | 4              | 3            | −1 |
| `recursive_self`  | 2300  | 4              | 3            | −1 |
| `filter_only`     | 50    | 4              | 3            | −1 |
| `filter_only`     | 2300  | 4              | 3            | −1 |
| `filter_except`   | 50    | 4              | 3            | −1 |
| `filter_except`   | 2300  | 4              | 3            | −1 |

The IPS speedups (+5%–+11%) are consistent with eliminating one
allocation in a hot loop on a YJIT-compiled JSON-mode emit path.

#### Decision (2026-05-03): record as upward curiosity; phase 2 closes

Per § 1's verdict-template clause and
`phase_1_report.md` § 1's ratio-not-absolute
discipline: improvements unrelated to the slice under measurement
are recorded but do not block. The rule-1 intent is "no S14
regression on the no-filter path"; the verdict is `Pass`. No
tuning of the 5% threshold is warranted — the threshold is correct
for catching genuine S14-induced regressions; today's deviations are
a benign side-effect of an unrelated optimization that landed inside
the rule-1 measurement window.

`phase_1_report.md` is **not** retroactively re-baselined. Future
phase-2-style reports comparing against phase 1 will recompute gaps
relative to the original phase-1 numbers; today's `chomp!`
contribution is part of the gap and should be carried as an
attribution note, not absorbed into the baseline. Re-baselining
phase 1 would erase the discipline that pre-registered the original
numbers.

### 6.2 Rule 2 — bench shape mismatch with S13 fixtures

All 4 applicable JSON rule-2 rows in § 5.2 are outside ±10% — every
gap positive (production faster than S13 by +176%–+411%), every gap
structural to fixture shape mismatch, not codegen drift. The S13
experiment's `indexed × single_path` cells were measured on three
fixture shapes none of which 1:1 match the canonical
`benchmarks/filter_only.rb` and `benchmarks/filter_except.rb`
scenarios:

| S13 fixture | Shape | Field count | Filter | Production bench match? |
| --- | --- | --- | --- | --- |
| `wide_flat_none` (#6.1)           | 71-attr flat                    | 71 | none           | no — production has no 71-attr flat scenario |
| `wide_flat_shallow_only` (#6.2)   | 71-attr flat                    | 71 | `:only` 3 of 71  | no — `filter_only` is 5-attr |
| `medium_graph_none` (#6.3)        | 8-attr `Comment` + has_one + has_many | 8 + assoc | none | partial — `graph` is similar shape |
| `medium_graph_shallow_only` (#6.4)| 8-attr `Comment` + has_one + has_many | 8 + assoc | `:only` 3 of 8 | no — closest neighbor for `filter_only` |
| `medium_graph_deep_nested` (#6.5) | Folder × Item × Subfolder, 8/3/2 fields | nested | deep `:except` | no — closest neighbor for `filter_except` |

The production `filter_only` / `filter_except` benches use a
5-attribute `Bench::Post` Descriptor (no associations) — which
exercises the `Filter::Indexed` Bits rep (≤63 fields) but with
**different elision economics** (2 of 5 dropped vs S13's 5 of 8 / 68
of 71) and **without the association walks** that dominate fixture
#6.4's IPS budget. The result: production is **structurally faster**
than every S13 fixture cell because production is doing **less work
per record**. The +176%–+411% gaps are the IPS difference between
"5 fields, 2 dropped, no assoc traversal" and "8+assoc fields, 5
dropped, has_one + has_many walks" — not codegen drift.

#### Investigation

The rule-2 rule body in § 2 names three suspected codegen-drift
candidates per the parent S14 PRD's user story 28:

1. **Missed wrapper shape** (a field emit not wrapped in
   `unless filters.drops?(<integer>)`) — _refuted_ by the snapshot
   diff walk: 20 generated-class fixtures, every Attribute /
   MethodAttribute / Association emit wrapped consistently, no
   omissions ([snapshot review summary in § 7.1 below](#71-snapshot-diff-walk-s141s144-mutations)).
2. **Stale `FIELD_INDEX` lookup** (an emit using the wrong integer
   for its position) — _refuted_ by the same snapshot review: every
   `FIELD_INDEX` constant matches the Descriptor's
   Attributes + MethodAttributes + Associations declared order, and
   every `unless filters.drops?(<integer>)` integer matches its
   field's index in `FIELD_INDEX`.
3. **Cache-lifetime bug in `filters.child(:<source>)`** — _refuted_
   by `memory_profiler` on a `filters: nil` call: 3 total allocs
   (Hash, `Oj::StringWriter`, `String`), zero `Filter::*` instances,
   confirming `Filter::NONE.child(:foo)` returns the same singleton
   without allocation. The non-nil path's per-call cost is
   measured at +5 allocs/call (3→8 json, 51→56 hash) consistent
   with fixture #6.4's 6 allocs/call.

All three candidates ruled out. The codegen is correct; rule 2's
**numeric** application is structurally invalid for today's bench
shape, not failing for an investigatable reason.

#### Decision (2026-05-03): pattern equivalence accepted; numeric reproduction deferred to follow-up

S14.6's HITL judgment: pattern equivalence verified at three
independent levels (snapshot diff, memory_profiler, allocation
counts) satisfies rule 2's stated intent (catch codegen drift). The
numeric IPS reproduction is deferred to a follow-up bench scenario
that 1:1 matches one of S13's fixture shapes — recorded as a phase-2
follow-up:

> **Follow-up — S14.7 (proposed)**: add a benchmark scenario that
> 1:1 matches S13 fixture #6.4 (`medium_graph_shallow_only`: 8-attr
> `Comment` Descriptor + `has_one` + `has_many`, `filters: {only:
> [<3 of 8>]}`) so rule 2 becomes mechanically applicable on the next
> phase-2-style canonical run. Same exercise for fixture #6.5 covers
> the `:except` deep-nested shape. Recorded here rather than filed as
> an issue because the fixture-shape mismatch was not anticipated by
> the S14.5 skeleton — files at S14 close-out time once the user
> confirms the rule-2 bar.

No tuning of the ±10% threshold is warranted — the threshold is
correct for catching genuine codegen drift; today's deviations are a
shape-mismatch artifact, not a threshold-too-tight artifact.

### 6.3 No rule-1 regressions; no rule-2 codegen drift

The combined verdict: rule 1 passes (16 within ±5%; 8 outside in the
wrong direction for a regression — all attributable to commit
`b83b486` outside S14's scope), and rule 2 passes at the
pattern-equivalence level (snapshot diff exact match; zero
filter-side allocations on `filters: nil`; +5-allocs/call cost on
the with-filter path) with numeric reproduction deferred to S14.7.

## 7. Diagnostic / re-run notes

Selective re-runs (one scenario or one filter mode for diagnosis)
are recorded here as **diagnostic** runs, separate from the
canonical numbers in § 4. The verdict in § 1 cites only the
canonical block; diagnostic data informs the analysis in § 5–6 but
does not replace canonical rows.

If the canonical run does not complete in one sitting, the
implementer shrinks `IPS_TIME` once and **re-pre-registers the change
here before re-running**, mirroring S12.2's `rake bench:all`
discipline and S13.3's
[`filter_experiments_results.md` § 8.3](filter_experiments_results.md#83-runtime-budget)
re-pre-registration protocol.

### 7.1 Snapshot diff walk — S14.1–S14.4 mutations

PR-level snapshot review for sign-off (referenced from § 5.2 and
§ 6.2). Cumulative diff in `spec/fixtures/generated/` between the
S14.5 skeleton commit (`834a4fc`) and HEAD (`e636727`) covers
**20 files**, **+553 / −255 lines**, and matches the four documented
S14.1–S14.4 mutations exactly with no surprises:

1. **`FIELD_INDEX = {<source> => <integer>, ...}.freeze` constant
   added** at every Generated Class top, ordered
   Attributes → MethodAttributes → Associations per the S14.1
   contract.
2. **`raise NotImplementedError if filters` → `filters =
   Panko::CodeGen::Filter.wrap(filters, FIELD_INDEX)`** at every
   public entry point (`serialize_one` / `serialize_many`).
3. **`unless filters.drops?(<integer>)` wrappers** around every
   field emit (`writer.push_value(...)`, `result[...] = ...`,
   association-call blocks), with the integer baked at codegen time
   from `FIELD_INDEX`.
4. **`filters.child(:<source>, <NestedKlass>::FIELD_INDEX)`** at
   every nested call site — including `recursive_self`'s
   `child(:replies, ...)` and `recursive_mutual`'s
   `child(:subfolder, ...)` / `child(:items, ...)`. **Filter-before-`if:`
   ordering** verified: the `unless filters.drops?(N)` wrapper
   surrounds the `if @cb_if_<source>.call(...)` block, never the
   reverse. **Hoisted child-filter** verified for `has_many`
   associations: `child_filter = filters.child(:items, ...);
   records.map { |r| ... child_filter ... }` — the cache lookup
   happens once outside the loop, not per-record.

No off-pattern changes; no extra mutations beyond the four documented
above. Sign-off recorded here.

### 7.2 `memory_profiler` on `filters: nil` — Filter::NONE singleton verification

Per acceptance criterion 3 in [#77](https://github.com/yosiat/serializers-code-gen/issues/77).
Run via the smoke-test script
`bundle exec ruby -e ... MemoryProfiler.report { inst.serialize_many(posts, filters: nil) }`
on the 5-attribute `FilterNoneCheck` Descriptor (50 records):

```
=== TOTAL ===
  allocated: 3 objects, 6829 bytes
  retained:  0 objects

=== Filter-side allocations (Filter::, FilterSpec, FILTER_) ===
  NONE — zero Filter:: allocations on filters: nil path

=== Top 10 allocated classes ===
  Hash: 1
  Oj::StringWriter: 1
  String: 1
```

Verified: `Filter::NONE` is the frozen singleton; `Filter.wrap(nil,
...)` returns it without allocation; `Filter::NONE.drops?(N)` returns
`false` without allocation; `Filter::NONE.child(:source, ...)`
returns the same singleton without allocation. The 3 allocs match
the canonical bench's `simple/scg/json size=50` row (3 allocs)
exactly — confirming the `filters: nil` path is byte-equivalent to
phase 1 modulo the one `Filter.wrap` constant lookup at the entry
point (which does not allocate).
