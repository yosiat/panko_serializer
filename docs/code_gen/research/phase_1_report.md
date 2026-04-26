# Phase 1 report — benchmark verdict

> **Status:** raw numbers + env recorded (S12.2). Verdict, hard-/soft-bar
> analysis, and beyond-sanity / scg-specific observations are still
> pending — that's S12.3's work and lives in §§ 1, 4, 5, 6, 7. This
> file's structure — verdict template, scenario list, hardware/env
> block, hard- and soft-bar table skeletons — was committed **before**
> any numbers were measured (S12.1), per the pre-registration discipline
> used for S13's filter experiment
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
| Ruby (`ruby -v`)                              | `ruby 4.0.2 (2026-03-17 revision d3da9fec82) +PRISM [arm64-darwin25]` |
| YJIT (`RubyVM::YJIT.enabled?` at run start)   | `on` — auto-enable fired via `RubyVM::YJIT.enable` in `benchmarks/support/setup.rb`; every per-scenario harness banner records `YJIT: on` |
| Hardware model                                | MacBook Pro (Mac16,5) |
| CPU                                           | Apple M4 Max — 16 cores (12 Performance + 4 Efficiency) |
| RAM                                           | 64 GB |
| OS                                            | macOS 26.3.1 (build 25D2128) |
| Run date                                      | 2026-04-26 |
| `bundle list \| grep -E 'panko\|oj_serializers'` | `panko_serializer (0.8.5)`, `oj_serializers (3.0.0)` |

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
Simple size=50/serializers_code_gen/json                       79.37K i/s ± 2.50%         4 allocs         0 retained
Simple size=50/serializers_code_gen/hash                       96.71K i/s ± 3.98%        51 allocs         0 retained
Simple size=50/panko/json                                      45.35K i/s ± 2.51%        20 allocs         0 retained
Simple size=50/panko/object                                    31.79K i/s ± 5.33%        71 allocs         0 retained
Simple size=50/oj_serializers/json                             59.16K i/s ± 3.97%       252 allocs         0 retained
Simple size=50/plain/json                                       8.53K i/s ± 4.27%       452 allocs         0 retained
Simple size=50/plain/hash                                      10.37K i/s ± 6.74%       451 allocs         0 retained
Simple size=2300/serializers_code_gen/json                      1.86K i/s ± 2.63%         4 allocs         0 retained
Simple size=2300/serializers_code_gen/hash                      2.15K i/s ± 5.67%      2301 allocs         0 retained
Simple size=2300/panko/json                                     1.02K i/s ± 2.54%        20 allocs         0 retained
Simple size=2300/panko/object                                  703.79 i/s ± 5.12%      2321 allocs         0 retained
Simple size=2300/oj_serializers/json                            1.31K i/s ± 3.66%     11502 allocs         0 retained
Simple size=2300/plain/json                                    186.11 i/s ± 4.84%     20702 allocs         0 retained
Simple size=2300/plain/hash                                    227.38 i/s ± 6.16%     20701 allocs         0 retained
```

#### 3.1.2 `has_one` — single has_one Association

```
HasOne size=50/serializers_code_gen/json                       55.95K i/s ± 2.47%         4 allocs         0 retained
HasOne size=50/serializers_code_gen/hash                       66.39K i/s ± 2.87%       101 allocs         0 retained
HasOne size=50/panko/json                                      28.19K i/s ± 2.51%        28 allocs         0 retained
HasOne size=50/panko/object                                    20.41K i/s ± 5.70%       129 allocs         0 retained
HasOne size=50/oj_serializers/json                             38.92K i/s ± 3.60%       302 allocs         0 retained
HasOne size=50/plain/json                                       4.87K i/s ± 8.13%      1252 allocs         0 retained
HasOne size=50/plain/hash                                       5.66K i/s ± 6.64%      1251 allocs         0 retained
HasOne size=2300/serializers_code_gen/json                      1.25K i/s ± 2.56%         4 allocs         0 retained
HasOne size=2300/serializers_code_gen/hash                      1.43K i/s ± 6.28%      4601 allocs         0 retained
HasOne size=2300/panko/json                                    641.61 i/s ± 2.81%        28 allocs         0 retained
HasOne size=2300/panko/object                                  455.73 i/s ± 5.92%      4629 allocs         0 retained
HasOne size=2300/oj_serializers/json                           854.38 i/s ± 0.94%     13802 allocs         0 retained
HasOne size=2300/plain/json                                    104.77 i/s ± 7.64%     57502 allocs         0 retained
HasOne size=2300/plain/hash                                    123.22 i/s ± 8.12%     57501 allocs         0 retained
```

#### 3.1.3 `has_many` — has_many Association

```
HasMany size=50/serializers_code_gen/json                      21.67K i/s ± 2.17%         4 allocs         0 retained
HasMany size=50/serializers_code_gen/hash                      19.34K i/s ± 9.98%       351 allocs         0 retained
HasMany size=50/panko/json                                     10.46K i/s ± 2.87%        78 allocs         0 retained
HasMany size=50/panko/object                                    7.44K i/s ± 5.31%       429 allocs         0 retained
HasMany size=50/oj_serializers/json                            16.43K i/s ± 3.28%       652 allocs         0 retained
HasMany size=50/plain/json                                      2.07K i/s ± 4.64%      2802 allocs         0 retained
HasMany size=50/plain/hash                                      2.40K i/s ± 6.12%      2801 allocs         0 retained
HasMany size=2300/serializers_code_gen/json                    477.79 i/s ± 2.51%         4 allocs         0 retained
HasMany size=2300/serializers_code_gen/hash                    450.98 i/s ± 2.00%     16101 allocs         0 retained
HasMany size=2300/panko/json                                   226.99 i/s ± 3.08%      2328 allocs         0 retained
HasMany size=2300/panko/object                                 157.98 i/s ± 7.60%     18429 allocs         0 retained
HasMany size=2300/oj_serializers/json                          355.49 i/s ± 3.09%     29902 allocs         0 retained
HasMany size=2300/plain/json                                    42.85 i/s ± 7.00%    128802 allocs         0 retained
HasMany size=2300/plain/hash                                    50.85 i/s ± 7.87%    128801 allocs         0 retained
```

#### 3.1.4 `method_attribute` — Method Attribute

```
MethodAttribute size=50/serializers_code_gen/json             114.60K i/s ± 2.90%         4 allocs         0 retained
MethodAttribute size=50/serializers_code_gen/hash             138.65K i/s ± 4.58%        51 allocs         0 retained
MethodAttribute size=50/panko/json                             59.40K i/s ± 2.78%        22 allocs         0 retained
MethodAttribute size=50/panko/object                           41.80K i/s ± 4.61%        73 allocs         0 retained
MethodAttribute size=50/oj_serializers/json                    98.58K i/s ± 2.81%       152 allocs         0 retained
MethodAttribute size=50/plain/json                             83.32K i/s ± 3.33%        52 allocs         0 retained
MethodAttribute size=50/plain/hash                            199.29K i/s ±12.36%        51 allocs         0 retained
MethodAttribute size=2300/serializers_code_gen/json             2.73K i/s ± 5.21%         4 allocs         0 retained
MethodAttribute size=2300/serializers_code_gen/hash             3.07K i/s ± 8.55%      2301 allocs         0 retained
MethodAttribute size=2300/panko/json                            1.42K i/s ± 3.03%        22 allocs         0 retained
MethodAttribute size=2300/panko/object                         964.58 i/s ± 5.81%      2323 allocs         0 retained
MethodAttribute size=2300/oj_serializers/json                   2.22K i/s ± 2.66%      6902 allocs         0 retained
MethodAttribute size=2300/plain/json                            1.90K i/s ± 5.04%      2302 allocs         0 retained
MethodAttribute size=2300/plain/hash                            4.02K i/s ± 3.98%      2301 allocs         0 retained
```

#### 3.1.5 `aliases` — Attribute name ≠ source

```
Aliases size=50/serializers_code_gen/json                      95.18K i/s ± 2.66%         4 allocs         0 retained
Aliases size=50/serializers_code_gen/hash                     122.42K i/s ± 2.78%        51 allocs         0 retained
Aliases size=50/panko/json                                     51.30K i/s ± 2.37%        20 allocs         0 retained
Aliases size=50/panko/object                                   36.69K i/s ± 5.94%        71 allocs         0 retained
Aliases size=50/oj_serializers/json                            73.52K i/s ± 1.17%       202 allocs         0 retained
Aliases size=50/plain/json                                     52.99K i/s ± 2.45%        52 allocs         0 retained
Aliases size=50/plain/hash                                    138.14K i/s ± 1.60%        51 allocs         0 retained
Aliases size=2300/serializers_code_gen/json                     2.22K i/s ± 2.71%         4 allocs         0 retained
Aliases size=2300/serializers_code_gen/hash                     2.73K i/s ± 7.55%      2301 allocs         0 retained
Aliases size=2300/panko/json                                    1.15K i/s ± 2.61%        20 allocs         0 retained
Aliases size=2300/panko/object                                 806.87 i/s ± 5.45%      2321 allocs         0 retained
Aliases size=2300/oj_serializers/json                           1.62K i/s ± 2.41%      9202 allocs         0 retained
Aliases size=2300/plain/json                                    1.16K i/s ± 1.38%      2302 allocs         0 retained
Aliases size=2300/plain/hash                                    3.07K i/s ± 9.33%      2301 allocs         0 retained
```

#### 3.1.6 `json_column` — Attribute backed by a JSON DB column

```
JsonColumn size=50/serializers_code_gen/json                   35.96K i/s ± 2.81%       154 allocs         0 retained
JsonColumn size=50/serializers_code_gen/hash                  200.14K i/s ± 2.91%        51 allocs         0 retained
JsonColumn size=50/panko/json                                  31.89K i/s ± 3.72%        70 allocs         0 retained
JsonColumn size=50/panko/object                                13.95K i/s ± 4.10%       571 allocs         0 retained
JsonColumn size=50/oj_serializers/json                         34.19K i/s ± 3.37%       252 allocs         0 retained
JsonColumn size=50/plain/json                                  61.91K i/s ± 4.79%        52 allocs         0 retained
JsonColumn size=50/plain/hash                                 237.29K i/s ± 5.11%        51 allocs         0 retained
JsonColumn size=2300/serializers_code_gen/json                 820.72 i/s ± 3.05%      6904 allocs         0 retained
JsonColumn size=2300/serializers_code_gen/hash                  4.55K i/s ± 8.37%      2301 allocs         0 retained
JsonColumn size=2300/panko/json                                715.42 i/s ± 2.66%      2320 allocs         0 retained
JsonColumn size=2300/panko/object                              299.87 i/s ± 7.00%     25321 allocs         0 retained
JsonColumn size=2300/oj_serializers/json                       770.21 i/s ± 5.45%     11502 allocs         0 retained
JsonColumn size=2300/plain/json                                 1.44K i/s ± 2.01%      2302 allocs         0 retained
JsonColumn size=2300/plain/hash                                 4.96K i/s ±15.98%      2301 allocs         0 retained
```

#### 3.1.7 `filter_only` — runtime `:only` (panko/oj); scg passes `filters: nil` per phase-1 contract

```
FilterOnly size=50/serializers_code_gen/json                   77.95K i/s ± 0.89%         4 allocs         0 retained
FilterOnly size=50/serializers_code_gen/hash                   93.96K i/s ± 2.19%        51 allocs         0 retained
FilterOnly size=50/panko/json                                  77.63K i/s ± 2.54%        22 allocs         0 retained
FilterOnly size=50/panko/object                                54.05K i/s ± 4.65%        73 allocs         0 retained
FilterOnly size=50/oj_serializers/json                        141.69K i/s ± 2.15%       102 allocs         0 retained
FilterOnly size=2300/serializers_code_gen/json                  1.80K i/s ± 0.78%         4 allocs         0 retained
FilterOnly size=2300/serializers_code_gen/hash                  2.08K i/s ± 6.40%      2301 allocs         0 retained
FilterOnly size=2300/panko/json                                 1.83K i/s ± 2.46%        22 allocs         0 retained
FilterOnly size=2300/panko/object                               1.23K i/s ± 7.02%      2323 allocs         0 retained
FilterOnly size=2300/oj_serializers/json                        3.25K i/s ± 2.03%      4602 allocs         0 retained
```

#### 3.1.8 `filter_except` — runtime `:except` (panko/oj); scg passes `filters: nil` per phase-1 contract

```
FilterExcept size=50/serializers_code_gen/json                 77.53K i/s ± 2.74%         4 allocs         0 retained
FilterExcept size=50/serializers_code_gen/hash                 94.24K i/s ± 2.00%        51 allocs         0 retained
FilterExcept size=50/panko/json                                51.49K i/s ± 2.46%        22 allocs         0 retained
FilterExcept size=50/panko/object                              34.76K i/s ± 5.01%        73 allocs         0 retained
FilterExcept size=50/oj_serializers/json                       73.75K i/s ± 4.08%       202 allocs         0 retained
FilterExcept size=2300/serializers_code_gen/json                1.79K i/s ± 0.72%         4 allocs         0 retained
FilterExcept size=2300/serializers_code_gen/hash                2.07K i/s ± 2.51%      2301 allocs         0 retained
FilterExcept size=2300/panko/json                               1.18K i/s ± 2.46%        22 allocs         0 retained
FilterExcept size=2300/panko/object                            781.28 i/s ± 6.78%      2323 allocs         0 retained
FilterExcept size=2300/oj_serializers/json                      1.65K i/s ± 1.51%      9202 allocs         0 retained
```

### 3.2 Beyond-sanity scenarios

#### 3.2.1 `wide_attributes` — ~70 Attributes; stresses per-Field emit/dispatch cost

```
WideAttributes size=50/serializers_code_gen/json                3.85K i/s ± 2.70%       754 allocs         0 retained
WideAttributes size=50/serializers_code_gen/hash                5.56K i/s ± 1.85%        51 allocs         0 retained
WideAttributes size=50/panko/json                               2.16K i/s ± 1.30%      2520 allocs         0 retained
WideAttributes size=50/panko/object                             1.60K i/s ± 2.43%      2321 allocs         0 retained
WideAttributes size=50/oj_serializers/json                      3.01K i/s ± 1.63%      4302 allocs         0 retained
WideAttributes size=50/plain/json                              741.89 i/s ± 2.43%       852 allocs         0 retained
WideAttributes size=50/plain/hash                              799.03 i/s ± 2.38%       851 allocs         0 retained
WideAttributes size=2300/serializers_code_gen/json              84.25 i/s ± 3.56%     34504 allocs         0 retained
WideAttributes size=2300/serializers_code_gen/hash             118.99 i/s ± 3.36%      2301 allocs         0 retained
WideAttributes size=2300/panko/json                             47.27 i/s ± 4.23%    115020 allocs         0 retained
WideAttributes size=2300/panko/object                           35.47 i/s ± 2.82%    105821 allocs         0 retained
WideAttributes size=2300/oj_serializers/json                    64.32 i/s ± 3.11%    197802 allocs         0 retained
WideAttributes size=2300/plain/json                             15.56 i/s ± 6.43%     39102 allocs         0 retained
WideAttributes size=2300/plain/hash                             16.99 i/s ± 5.89%     39101 allocs         0 retained
```

#### 3.2.2 `graph` — entrypoint with Attributes + multiple has_one + multiple has_many

```
Graph size=50/serializers_code_gen/json                         9.34K i/s ± 2.44%       154 allocs         0 retained
Graph size=50/serializers_code_gen/hash                         8.61K i/s ± 9.35%       751 allocs         0 retained
Graph size=50/panko/json                                        5.02K i/s ± 2.55%       248 allocs         0 retained
Graph size=50/panko/object                                      3.57K i/s ± 4.29%       849 allocs         0 retained
Graph size=50/oj_serializers/json                               6.72K i/s ± 3.51%      1502 allocs         0 retained
Graph size=50/plain/json                                        1.75K i/s ± 5.53%      3352 allocs         0 retained
Graph size=50/plain/hash                                        1.99K i/s ± 9.36%      3351 allocs         0 retained
Graph size=2300/serializers_code_gen/json                      192.71 i/s ± 3.11%      6904 allocs         0 retained
Graph size=2300/serializers_code_gen/hash                      191.69 i/s ± 6.78%     34501 allocs         0 retained
Graph size=2300/panko/json                                     104.00 i/s ± 3.85%      9248 allocs         0 retained
Graph size=2300/panko/object                                    73.05 i/s ± 5.48%     36849 allocs         0 retained
Graph size=2300/oj_serializers/json                            140.31 i/s ± 4.99%     69002 allocs         0 retained
Graph size=2300/plain/json                                      36.19 i/s ± 8.29%    154102 allocs         0 retained
Graph size=2300/plain/hash                                      42.40 i/s ± 7.08%    154101 allocs         0 retained
```

### 3.3 scg-specific scenarios

#### 3.3.1 `scg_generic_vs_specialized` — Models: nil vs Models: [Post], same shape

```
ScgGenericVsSpecialized size=50/serializers_code_gen/json[generic]     74.04K i/s ± 2.71%         4 allocs         0 retained
ScgGenericVsSpecialized size=50/serializers_code_gen/hash[generic]     90.69K i/s ± 2.01%        51 allocs         0 retained
ScgGenericVsSpecialized size=50/serializers_code_gen/json[specialized]     82.09K i/s ± 2.65%         4 allocs         0 retained
ScgGenericVsSpecialized size=50/serializers_code_gen/hash[specialized]     98.73K i/s ± 3.74%        51 allocs         0 retained
ScgGenericVsSpecialized size=2300/serializers_code_gen/json[generic]      1.66K i/s ± 3.25%         4 allocs         0 retained
ScgGenericVsSpecialized size=2300/serializers_code_gen/hash[generic]      1.93K i/s ± 6.94%      2301 allocs         0 retained
ScgGenericVsSpecialized size=2300/serializers_code_gen/json[specialized]      1.87K i/s ± 2.30%         4 allocs         0 retained
ScgGenericVsSpecialized size=2300/serializers_code_gen/hash[specialized]      2.16K i/s ± 8.47%      2301 allocs         0 retained
```

#### 3.3.2 `scg_skip_elision` — MethodAttribute returning SKIP on half the records vs control

```
ScgSkipElision size=50/serializers_code_gen/json[skip_fires_half]    115.28K i/s ± 3.32%         4 allocs         0 retained
ScgSkipElision size=50/serializers_code_gen/hash[skip_fires_half]    129.82K i/s ± 2.70%        51 allocs         0 retained
ScgSkipElision size=50/serializers_code_gen/json[skip_never_fires]    118.05K i/s ± 1.04%         4 allocs         0 retained
ScgSkipElision size=50/serializers_code_gen/hash[skip_never_fires]    136.14K i/s ± 6.85%        51 allocs         0 retained
ScgSkipElision size=2300/serializers_code_gen/json[skip_fires_half]      2.68K i/s ± 0.75%         4 allocs         0 retained
ScgSkipElision size=2300/serializers_code_gen/hash[skip_fires_half]      2.88K i/s ± 8.88%      2301 allocs         0 retained
ScgSkipElision size=2300/serializers_code_gen/json[skip_never_fires]      2.78K i/s ± 2.51%         4 allocs         0 retained
ScgSkipElision size=2300/serializers_code_gen/hash[skip_never_fires]      3.05K i/s ± 9.08%      2301 allocs         0 retained
```

#### 3.3.3 `scg_recursive` — Comment self-reference, 3-level tree (recursive_self shape)

```
ScgRecursive size=50/serializers_code_gen/json                 10.16K i/s ± 2.59%         4 allocs         0 retained
ScgRecursive size=50/serializers_code_gen/hash                  8.51K i/s ± 8.68%       701 allocs         0 retained
ScgRecursive size=2300/serializers_code_gen/json               210.35 i/s ± 3.33%         4 allocs         0 retained
ScgRecursive size=2300/serializers_code_gen/hash               190.09 i/s ± 1.58%     32201 allocs         0 retained
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
