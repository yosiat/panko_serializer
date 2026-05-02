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

_Pending canonical run._ One paragraph will land here once S13.3 fills
in the per-fixture tables in § 6 and applies the decision rule from § 2.
The paragraph will record:

- The winning cell from `{Hash-wrapper, Set-index} × {single-path,
  dual-path}`.
- Which clause of the pre-registered decision rule (§ 2) settled the
  choice — Pareto-dominance, worst-fixture-row 5% noise, or simplicity
  tiebreak.
- The runner-up cell and its gap to the winner (so a future re-tuning
  experiment has the prior gap on record per [`#55` user
  story 24](https://github.com/yosiat/serializers-code-gen/issues/55)).
- Any anomalies — a divergent hash-mode parity result (§ 7), a fixture
  where the loser was within 1%, or an unexpected dominance pattern.
- A pointer to the cell's bench-file source so S14 can lift it into
  `lib/serializers_code_gen/filters/<winner>.rb` with minimal
  restructuring.

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
the canonical run exercises **only** these 4 cells × 5 fixtures × N
sizes — no extra ad-hoc rows added during the run. Selective re-runs (one
cell on one fixture for diagnosis) are recorded in § 8 as **diagnostic**
runs, separate from the canonical numbers.

## 4. Pre-registered cells

The 2×2 internal-representation × emit-strategy matrix, plus a reference
row. All four cells expose the same internal interface — `drops?(name)`,
`child(source)`, `none?` — per [`docs/filters.md` § Threading through
Composition](../filters.md#threading-through-composition); the only
thing that varies between cells is the implementation, not the
contract. The two emit strategies (single-path vs dual-path) are not
extra Filter classes — they're a per-fixture toggle on the compiled
**Generated Class** body (dual-path overlays paired
`_write_one_unfiltered` / `_write_one_filtered` bodies + a tiny
dispatcher; single-path uses the compiled body as-is).

| Row | Cell                          | Internal representation | Emit strategy | Notes                                                                             |
| --- | ----------------------------- | ----------------------- | ------------- | --------------------------------------------------------------------------------- |
| 1   | `hash_wrapper × single_path`  | Hash-wrapper            | single-path   | Wraps the caller's Hash; `drops?` does direct Hash lookups + `Array#include?`.    |
| 2   | `hash_wrapper × dual_path`    | Hash-wrapper            | dual-path     | Same Hash-wrapper representation; emit overlays paired bodies + dispatcher.       |
| 3   | `set_index × single_path`     | Set-index               | single-path   | Walks the Hash once at entry; per-level `Set`s + cached child Filter objects.     |
| 4   | `set_index × dual_path`       | Set-index               | dual-path     | Same Set-index representation; emit overlays paired bodies + dispatcher.          |
| ref | `reference (no filter machinery)` | n/a                 | n/a           | Filter-machinery-absent variant — the unmodified phase-1 emit body. Ceiling row.  |

The reference row establishes the ceiling that any of the 4 cells is
expected to approach on the no-filter path. `Filter::NONE`'s allocation
profile (zero filter-side allocations on a no-filter call) is reported
inline with the cell rows in § 6 — see [`docs/filters.md` § No-filter
fast path](../filters.md#no-filter-fast-path).

## 5. Hardware / env

Filled in immediately before the canonical run (S13.3). Reproducibility
matters more than the specific hardware — anyone re-running the bench
should be able to compare apples-to-apples or note the hardware delta.
Same field set as [`phase_1_report.md` § 2](phase_1_report.md) and
[`ar_access_results.md` § 1](ar_access_results.md).

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

Each table has 5 rows (4 cells + reference) and 2 columns per size
(`ips`, `allocs`). Cells are empty pending S13.3; the `Δ vs reference`
column is computed from the `ips` column once both are filled and reads
"+x.x% / −x.x%" relative to the reference row at that size.

### 6.1 Fixture #1 — `wide_flat_none`

| Cell                              | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs | Δ vs reference (ips) |
| --------------------------------- | ----------- | -------------- | ------------- | ---------------- | -------------------- |
| `hash_wrapper × single_path`      |             |                |               |                  |                      |
| `hash_wrapper × dual_path`        |             |                |               |                  |                      |
| `set_index × single_path`         |             |                |               |                  |                      |
| `set_index × dual_path`           |             |                |               |                  |                      |
| `reference (no filter machinery)` |             |                |               |                  | n/a (ceiling)        |

### 6.2 Fixture #2 — `wide_flat_shallow_only`

| Cell                              | size=1 ips | size=1 allocs | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs | Δ vs reference (ips) |
| --------------------------------- | ---------- | ------------- | ----------- | -------------- | ------------- | ---------------- | -------------------- |
| `hash_wrapper × single_path`      |            |               |             |                |               |                  |                      |
| `hash_wrapper × dual_path`        |            |               |             |                |               |                  |                      |
| `set_index × single_path`         |            |               |             |                |               |                  |                      |
| `set_index × dual_path`           |            |               |             |                |               |                  |                      |
| `reference (no filter machinery)` |            |               |             |                |               |                  | n/a (ceiling)        |

### 6.3 Fixture #3 — `medium_graph_none`

| Cell                              | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs | Δ vs reference (ips) |
| --------------------------------- | ----------- | -------------- | ------------- | ---------------- | -------------------- |
| `hash_wrapper × single_path`      |             |                |               |                  |                      |
| `hash_wrapper × dual_path`        |             |                |               |                  |                      |
| `set_index × single_path`         |             |                |               |                  |                      |
| `set_index × dual_path`           |             |                |               |                  |                      |
| `reference (no filter machinery)` |             |                |               |                  | n/a (ceiling)        |

### 6.4 Fixture #4 — `medium_graph_shallow_only`

| Cell                              | size=1 ips | size=1 allocs | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs | Δ vs reference (ips) |
| --------------------------------- | ---------- | ------------- | ----------- | -------------- | ------------- | ---------------- | -------------------- |
| `hash_wrapper × single_path`      |            |               |             |                |               |                  |                      |
| `hash_wrapper × dual_path`        |            |               |             |                |               |                  |                      |
| `set_index × single_path`         |            |               |             |                |               |                  |                      |
| `set_index × dual_path`           |            |               |             |                |               |                  |                      |
| `reference (no filter machinery)` |            |               |             |                |               |                  | n/a (ceiling)        |

### 6.5 Fixture #5 — `medium_graph_deep_nested`

| Cell                              | size=1 ips | size=1 allocs | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs | Δ vs reference (ips) |
| --------------------------------- | ---------- | ------------- | ----------- | -------------- | ------------- | ---------------- | -------------------- |
| `hash_wrapper × single_path`      |            |               |             |                |               |                  |                      |
| `hash_wrapper × dual_path`        |            |               |             |                |               |                  |                      |
| `set_index × single_path`         |            |               |             |                |               |                  |                      |
| `set_index × dual_path`           |            |               |             |                |               |                  |                      |
| `reference (no filter machinery)` |            |               |             |                |               |                  | n/a (ceiling)        |

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
| `hash_wrapper × single_path`      |            |               |             |                |               |                  |
| `hash_wrapper × dual_path`        |            |               |             |                |               |                  |
| `set_index × single_path`         |            |               |             |                |               |                  |
| `set_index × dual_path`           |            |               |             |                |               |                  |
| `reference (no filter machinery)` |            |               |             |                |               |                  |

**Parity verdict.** _Pending canonical run._ One sentence will land
here once S13.3 fills in the table above: either "hash-mode winner
matches json-mode winner — parity confirmed" (with the cell named) or
"hash-mode winner diverges — investigation halts cell selection" (with
the divergence documented).

## 8. Diagnostic / re-run notes

_To be filled if any._ Per [`#55` user story 28](https://github.com/yosiat/serializers-code-gen/issues/55):
selective re-runs (one cell on one fixture for diagnosis) are recorded
here as **diagnostic** runs, separate from the canonical numbers in
§§ 6–7. The verdict in § 1 cites only the canonical block; diagnostic
data informs the analysis but does not replace canonical rows.

If the canonical run does not complete in one sitting (the runtime
budget per [`#55` user story 34](https://github.com/yosiat/serializers-code-gen/issues/55)
is ~30–40 minutes — `IPS_TIME=5` × warmup=3 × ~25 rows × 4 cells × 5
fixtures × ~2.5 sizes per fixture), the implementer shrinks `IPS_TIME`
once and **re-pre-registers the change here before re-running**. The
discipline mirrors S12.2's `rake bench:all` protocol.
