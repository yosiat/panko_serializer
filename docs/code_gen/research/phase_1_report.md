# Phase 1 report — benchmark verdict

> **Status:** pre-registered skeleton. Numbers are pending the canonical
> `rake bench:all` run on dev hardware (S12.2). This file's structure —
> verdict template, scenario list, hardware/env block, hard- and soft-bar
> table skeletons — was committed **before** any numbers were measured, per
> the pre-registration discipline used for S13's filter experiment
> ([`docs/filters.md` § Experiment design](../filters.md#experiment-design)).
> Writing down what's being measured before measuring it prevents the
> verdict from being retro-fitted to the numbers.

This is the canonical phase-1 baseline against which S13 (filter
experiment) and S14 (filter implementation) measure filter overhead, per
[`docs/phase-1-bar.md` § 3 Benchmark verdict recorded](../phase-1-bar.md#3-benchmark-verdict-recorded).
The shape matches the [`docs/research/`](README.md) convention (summary
verdict at top, raw numbers, analysis) — see
[`ar_access_results.md`](ar_access_results.md) for the template this
report follows.

## 1. Verdict

_Pending canonical run._ One paragraph will land here once S12.2 fills in
the raw numbers and S12.3 walks the hard bar clause-by-clause. The
paragraph will record:

- Pass/fail per hard-bar sub-clause from
  [`docs/phase-1-bar.md` § 4 Performance bar met](../phase-1-bar.md#4-performance-bar-met)
  — `scg/json ≥ panko/json`, `scg/hash ≥ panko/object`, allocations
  `scg ≤ panko`, "strictly beats Panko on at least half of the sanity
  scenarios".
- The decision: phase 1 closed, bar tuned (with a citation to the new
  clause in `docs/phase-1-bar.md`), or fixes landed and re-run (with a
  pointer to the iteration recorded in § 8).
- Soft-bar gaps (`scg/json` vs `oj_serializers/json`) >10% recorded but
  not blocking, per
  [`docs/phase-1-bar.md` § Soft bar](../phase-1-bar.md#soft-bar--measured-recorded-does-not-block).

## 2. Hardware / env

Filled in immediately before the canonical run. Reproducibility matters
more than the specific hardware — anyone re-running the bench should be
able to compare apples-to-apples or note the hardware delta.

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

## 3. Raw numbers

Stdout tables copied verbatim from the harness — one block per scenario
per size. Reformatting is forbidden (it can hide rounding or row-omission
errors per the parent PRD). The canonical numbers come from a single
`rake bench:all` invocation at sizes `[50, 2300]` per
[`docs/benchmarks.md` § Fixture data](../benchmarks.md#fixture-data); per-scenario
re-runs (`BENCH=<substr>`) are diagnostic only and do not replace the
canonical block.

All 13 scenarios from
[`docs/benchmarks.md` § Directory layout](../benchmarks.md#directory-layout--scenario-centric)
appear below. The 8 sanity scenarios populate the hard bar in § 4; the 2
beyond-sanity and 3 scg-specific scenarios are recorded for reference per
[`docs/phase-1-bar.md` § What's not in the bar](../phase-1-bar.md#whats-not-in-the-bar)
and write up in §§ 6–7.

### 3.1 Sanity scenarios

#### 3.1.1 `simple` — flat Attributes

```
[size=50]   pending
[size=2300] pending
```

#### 3.1.2 `has_one` — single has_one Association

```
[size=50]   pending
[size=2300] pending
```

#### 3.1.3 `has_many` — has_many Association

```
[size=50]   pending
[size=2300] pending
```

#### 3.1.4 `method_attribute` — Method Attribute

```
[size=50]   pending
[size=2300] pending
```

#### 3.1.5 `aliases` — Attribute name ≠ source

```
[size=50]   pending
[size=2300] pending
```

#### 3.1.6 `json_column` — Attribute backed by a JSON DB column

```
[size=50]   pending
[size=2300] pending
```

#### 3.1.7 `filter_only` — runtime `:only` (panko/oj); scg passes `filters: nil` per phase-1 contract

```
[size=50]   pending
[size=2300] pending
```

#### 3.1.8 `filter_except` — runtime `:except` (panko/oj); scg passes `filters: nil` per phase-1 contract

```
[size=50]   pending
[size=2300] pending
```

### 3.2 Beyond-sanity scenarios

#### 3.2.1 `wide_attributes` — ~70 Attributes; stresses per-Field emit/dispatch cost

```
[size=50]   pending
[size=2300] pending
```

#### 3.2.2 `graph` — entrypoint with Attributes + multiple has_one + multiple has_many

```
[size=50]   pending
[size=2300] pending
```

### 3.3 scg-specific scenarios

#### 3.3.1 `scg_generic_vs_specialized` — Models: nil vs Models: [Post], same shape

```
[size=50]   pending
[size=2300] pending
```

#### 3.3.2 `scg_skip_elision` — MethodAttribute returning SKIP on half the records vs control

```
[size=50]   pending
[size=2300] pending
```

#### 3.3.3 `scg_recursive` — Comment self-reference, 3-level tree (recursive_self shape)

```
[size=50]   pending
[size=2300] pending
```

## 4. Hard-bar analysis

Per [`docs/phase-1-bar.md` § Hard bar](../phase-1-bar.md#hard-bar--blocks-moving-to-phase-2),
across every **sanity** scenario, at both sizes `[50, 2300]`:

1. **Clause A** — `serializers_code_gen/json` ≥ `panko/json` (ips).
2. **Clause B** — `serializers_code_gen/hash` ≥ `panko/object` (ips).
3. **Clause C** — Allocations: scg rows ≤ Panko rows per scenario.
4. **Clause D** (aggregate) — Strictly beats Panko on at least half of
   the sanity scenarios. Tally below the table.

"≥" is interpreted as **within 5% noise floor, or strictly better** per
the bar. "Strictly beats" is a per-row indicator — scg is measurably
faster (outside the 5% noise floor) than Panko on **both** mode pairs at
that scenario+size; the per-row Yes/No values feed the Clause D tally.

### 4.1 Clause-by-clause table — sanity scenarios × sizes

| Scenario           | Size | Clause A: scg/json vs panko/json | Clause B: scg/hash vs panko/object | Clause C: allocs scg ≤ panko | Strictly beats? |
| ------------------ | ---- | -------------------------------- | ---------------------------------- | ---------------------------- | --------------- |
| `simple`           | 50   |                                  |                                    |                              |                 |
| `simple`           | 2300 |                                  |                                    |                              |                 |
| `has_one`          | 50   |                                  |                                    |                              |                 |
| `has_one`          | 2300 |                                  |                                    |                              |                 |
| `has_many`         | 50   |                                  |                                    |                              |                 |
| `has_many`         | 2300 |                                  |                                    |                              |                 |
| `method_attribute` | 50   |                                  |                                    |                              |                 |
| `method_attribute` | 2300 |                                  |                                    |                              |                 |
| `aliases`          | 50   |                                  |                                    |                              |                 |
| `aliases`          | 2300 |                                  |                                    |                              |                 |
| `json_column`      | 50   |                                  |                                    |                              |                 |
| `json_column`      | 2300 |                                  |                                    |                              |                 |
| `filter_only`      | 50   |                                  |                                    |                              |                 |
| `filter_only`      | 2300 |                                  |                                    |                              |                 |
| `filter_except`    | 50   |                                  |                                    |                              |                 |
| `filter_except`    | 2300 |                                  |                                    |                              |                 |

### 4.2 Clause D — "strictly beats" tally

Counted across the 8 sanity scenarios. A scenario contributes to the tally
if **both** sizes (50 and 2300) show "Strictly beats? = Yes" in § 4.1 —
the bar is verified per scenario, not per row.

| | |
| --- | --- |
| Sanity scenarios where scg strictly beats Panko at both sizes | _pending_ / 8 |
| Threshold (at least half)                                     | 4 / 8         |
| Clause D verdict                                              | _pending_     |

## 5. Soft-bar analysis

Per [`docs/phase-1-bar.md` § Soft bar](../phase-1-bar.md#soft-bar--measured-recorded-does-not-block).
`oj_serializers/json` is the comparison. Recorded across every sanity
scenario at both sizes; gaps >10% get a one-paragraph investigation note
in § 5.2. Soft bar **does not block** phase-1 closeout.

### 5.1 scg/json vs oj_serializers/json — sanity scenarios × sizes

| Scenario           | Size | scg/json ips | oj_serializers/json ips | Gap (%) | Flagged? |
| ------------------ | ---- | ------------ | ----------------------- | ------- | -------- |
| `simple`           | 50   |              |                         |         |          |
| `simple`           | 2300 |              |                         |         |          |
| `has_one`          | 50   |              |                         |         |          |
| `has_one`          | 2300 |              |                         |         |          |
| `has_many`         | 50   |              |                         |         |          |
| `has_many`         | 2300 |              |                         |         |          |
| `method_attribute` | 50   |              |                         |         |          |
| `method_attribute` | 2300 |              |                         |         |          |
| `aliases`          | 50   |              |                         |         |          |
| `aliases`          | 2300 |              |                         |         |          |
| `json_column`      | 50   |              |                         |         |          |
| `json_column`      | 2300 |              |                         |         |          |
| `filter_only`      | 50   |              |                         |         |          |
| `filter_only`      | 2300 |              |                         |         |          |
| `filter_except`    | 50   |              |                         |         |          |
| `filter_except`    | 2300 |              |                         |         |          |

### 5.2 Investigation notes (gaps >10%)

_To be filled in S12.3 if any row in § 5.1 shows a gap >10%. Each note is
one paragraph: where oj_serializers wins, a hypothesis for why
(hand-rolled C path? hot-path mismatch?), and whether closing the gap is
worth pursuing in phase 2._

## 6. Beyond-sanity scenarios — observations

Per [`docs/phase-1-bar.md` § What's not in the bar](../phase-1-bar.md#whats-not-in-the-bar):
recorded for reference, **do not gate phase 1**. The shapes are still
fluid per [`docs/benchmarks.md` § Open refinements](../benchmarks.md#open-refinements);
gating phase 1 on them would force the implementer to lock down a
fluid spec.

### 6.1 `wide_attributes`

_Brief observation pending: how does scg/json compare to panko/json and
oj_serializers/json at ~70 Attributes? Any allocation surprises at the
per-Field emit boundary?_

### 6.2 `graph`

_Brief observation pending: how does scg handle the combined Composition
shape (~5 Attributes + 2 has_one + 2 has_many) versus Panko's nested
serializer chain?_

## 7. scg-specific scenarios — observations

These three scenarios compare scg variants against each other (no Panko /
oj_serializers row). Recorded as the canonical baseline for "Generic
costs X% more than Specialized at depth Y" claims that may surface in
later docs or phase-2 work.

### 7.1 `scg_generic_vs_specialized`

_Brief observation pending: how much does the Specialized path
(`record._read_attribute("name")` + `models: [Post]`) buy over the
Generic path's `_write_one_object` / `record.send(:name)` dispatch on the
same flat shape?_

### 7.2 `scg_skip_elision`

_Brief observation pending: what does the SKIP-handling guard
(`unless value.equal?(SerializersCodeGen::SKIP)`) cost when SKIP fires on
half the records, vs an unconditional control with the same shape?_

### 7.3 `scg_recursive`

_Brief observation pending: how does the self-recursion shortcut
(`@replies_serializer = self`, no allocation per recursive level) hold up
across a 3-level Comment tree (1 + 2 + 4 = 7 nodes per root)?_

## 8. Decisions for failing scenarios

_To be filled if any._ Per the parent PRD's **fix vs tune** protocol:

- **Fix** when a profile reveals a tractable hot path. `PROFILE=cpu`
  (StackProf) and `PROFILE=memory` (MemoryProfiler) per
  [`docs/benchmarks.md` § Env knobs](../benchmarks.md#core-features-carried-over)
  identify hot frames and allocation hot spots; a TDD'd focused
  regression spec pins the invariant; the optimization lifts it green;
  the canonical bench re-runs in full.
- **Tune** when the gap is structural and the original target was
  overstated.
  [`docs/phase-1-bar.md` § Tuning](../phase-1-bar.md#tuning) explicitly
  invites this; the discipline is "write the new bar down before
  deciding phase 1 is done", not "never tune". Any tuning updates
  `docs/phase-1-bar.md` with the new clause + rationale, and the verdict
  in § 1 above cites the new clause by section heading.

Default: fix first, tune as fallback. Each failing scenario gets its own
sub-section here recording: what was profiled, what was changed (or what
clause was tuned and why), and the iteration's number block (re-run
output if a fix landed).
