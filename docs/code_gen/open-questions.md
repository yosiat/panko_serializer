# Open questions

Design threads not yet resolved. Each one has a rough shape proposed but awaits
confirmation. Record-access strategy is fully resolved across
[compilation.md](compilation.md), [config.md](config.md), [descriptor.md](descriptor.md),
and the research notes in [research/](research/). Missing-value behavior for the generic
path (raise `NoMethodError` naturally, return `nil` for missing Hash keys) is documented
in `descriptor.md` — kept simple, no knobs. Public API surface, gem layout, and the
**Compiler** / **Generator** / **Code Builder** layering are locked in
[structure.md](structure.md). No per-Rails-version adapter code — the supported Rails
versions share a stable API; the CI matrix exercises all combinations (see
[ci.md](ci.md)). Testing strategy is fully captured in [testing.md](testing.md). CI
matrix, Appraisal wiring, lint choice, benchmark-in-CI policy, and lefthook hooks are
fully resolved in [ci.md](ci.md).

## Filters

Public shape locked — nested Hash matching Panko's current format. Full spec in
[filters.md](filters.md). Remaining sub-threads:

- **Dual-path emit — experiment-driven.** Emit `_write_one_unfiltered` +
  `_write_one_filtered` per **Generated Class** and dispatch once at `_write_one` entry,
  vs a single filter-aware path that always consults the Null-Object Filter. Chosen by
  benchmark. See the "Dual-path emit" section of [filters.md](filters.md).
- **Internal representation — experiment-driven.** Thin Hash wrapper vs pre-normalized
  per-call index (e.g., `Set`s). Chosen by benchmark. See the "Internal representation"
  section of [filters.md](filters.md).
- **JSON vs Hash parity**: semantics identical, emit paths differ. Documented; confirm at
  implementation time.

## Testing strategy

Locked — see [testing.md](testing.md). No remaining sub-threads; the feature-test
coverage matrix for cross-cutting concerns is fully captured in
[testing.md § Feature-test organization](testing.md#feature-test-organization).

## Benchmarks

- `benchmark-ips` for micro; `memory_profiler` for allocation tracking.
- Benchmark targets:
  - vs. Panko (current implementation)
  - vs. ActiveModel::Serializers
  - vs. plain `to_json` / `as_json`
- Benchmark fixtures: a shallow model (id + few cols), a model with **Method Attributes**,
  a model with nested **Associations**, a deep-nested model.
- Regression guard: CI is **not** the gate (see [ci.md § Benchmarks in CI](ci.md#benchmarks-in-ci))
  — benchmarks run on dev hardware pre-release against a committed baseline. Baseline
  file format and comparison-tool choice are the remaining sub-threads.
