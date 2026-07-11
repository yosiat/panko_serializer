# Phase 1 bar

Phase 1 of the initial release ("pre-filter core") is complete when all four
clauses below hold. Meeting the bar is the trigger to move to phase 2 (filters);
it does not itself release the library. See [`goals.md` § Phasing](goals.md#phasing)
for how phase 1 fits into the overall release sequence.

## 1. Feature coverage

Every feature in phase-1 scope is implemented and covered by the feature-test
matrix defined in [`testing.md`](testing.md). Snapshot corpus is green.
Feature-level specs and integration specs are green.

**Phase-1 scope**: **Attributes**, **Method Attributes** (including **SKIP**),
**Associations** (both **Kinds**, with `if:` **Callable**), **Context** threading,
**Config** (all fields), both **Output Modes** (`:json` + `:hash`), **Root Key**,
**Generic path** and **Specialized path**, **Recursive Descriptor** support.

**Out of phase-1 scope**: **Filters** (phase 2), **Dump** (phase 3).

## 2. CI green on full matrix

The 5-cell CI matrix defined in [`ci.md`](ci.md) passes:
`{ruby: [3.4, 4.0]} × {rails: [7.2, 8.0, 8.1]}` minus `{ruby: 4.0, rails: 7.2}`.
standardrb is clean. Lefthook pre-commit runs clean on a representative change.

## 3. Benchmark verdict recorded

The full benchmark harness defined in [`benchmarks.md`](benchmarks.md) runs on every
scenario listed there. Numbers are copied into a **phase-1 report** — not release
notes, not `docs/research/`. The report serves as the baseline against which
phase 2's filter overhead is measured.

The report lives at `docs/research/phase_1_report.md`, structured to match the
`docs/research/` convention (summary verdict at top, raw numbers, analysis).

## 4. Performance bar met

### Hard bar — blocks moving to phase 2

Against `panko/json` and `panko/object`, at both sizes `[50, 2300]`, across every
sanity scenario:

- `serializers_code_gen/json` **≥** `panko/json` (ips).
- `serializers_code_gen/hash` **≥** `panko/object` (ips).
- Allocations: scg rows **≤** Panko rows per scenario, **except** the `json_column`
  scenario (see carve-out below).
- Strictly beats Panko on **at least half** of the sanity scenarios.

"≥" means "within 5% noise floor, or strictly better". The bar accepts ties within
noise; it rejects measurable regressions.

#### `json_column` allocation carve-out

For the `json_column` scenario only, the allocation clause reads:

- `serializers_code_gen/json` allocations **≤** today's `serializers_code_gen/json`
  allocations on the same scenario (a self-comparison, not a Panko-comparison).

**Rationale**: with the `:wire_format` emit shape (S12.5 / #60), scg sits at ~2 allocs
per record on `json_column` vs Panko's ~1. The residual alloc is `Oj.sc_parse`'s
working-state object, which is structural — closing it requires either a custom
byte-scan validator or a `:trusted` mode that skips validation entirely. Both are out of
scope for #60 and warrant a separate slice if pursued. The carve-out records the
decision to prioritize IPS (where scg comfortably beats Panko on this scenario) over
strict alloc parity.

If any clause fails, phase 1 does not end. The implementer profiles the failing
scenario, applies fixes, re-runs. If the gap is structural (no fix identified),
phase 1 explicitly reopens the perf target rather than quietly redefining it.

### Soft bar — measured, recorded, does not block

Against `oj_serializers/json`, at both sizes, across every sanity scenario:

- `serializers_code_gen/json` **≥** `oj_serializers/json` (ips).

Material gaps (>10%) are called out in the phase-1 report with an investigation
note. Whether to block phase 2 or move on with the gap documented is decided
case-by-case — the gap does not automatically freeze the pipeline.

### Asymmetry rationale

Panko is the library this one replaces. Losing to Panko invalidates the project
thesis — this is the load-bearing claim.

Oj-Serializers uses hand-written C on some hot paths. Matching it from pure-Ruby
codegen + YJIT is a stretch goal, not a ship criterion. Making it a hard bar would
commit to a match we haven't scouted.

## What's not in the bar

- No `plain/json` or `plain/hash` comparison required. Those rows are context, not
  competitive targets.
- No YJIT-off numbers required. YJIT is the production runtime target.
- Beyond-sanity scenarios (`wide_attributes`, `graph`) are measured and recorded but
  do not gate phase 1 if their shape is still fluid per
  [`benchmarks.md` § Open refinements](benchmarks.md#open-refinements).

## Tuning

The implementer reserves the right to tune this bar at implementation time. Treat
this document as a captured decision, not a frozen contract — if real numbers
reveal the bar is too strict or too loose, update this file. The discipline that
matters is **writing the new bar down before deciding phase 1 is done**, not
keeping the original bar pristine.
