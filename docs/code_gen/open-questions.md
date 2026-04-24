# Open questions

Design threads not yet resolved. Everything in `docs/` is otherwise locked.
Before adding anything here, check [`deferred.md`](deferred.md) to be sure a
topic isn't deliberately punted.

## No design questions remain

All design threads for the initial release are locked in the corresponding doc
under [`docs/`](README.md). The only thing still to happen is **execution** — in
particular, the filter-implementation experiment, which is pre-designed but not
yet run.

## Execution pending: filter experiment

Scheduled for **phase 2** of the initial release. Phase 1 (pre-filter core) is
tracked against [`phase-1-bar.md`](phase-1-bar.md); when that bar is met, phase 2
begins and the experiment runs.

The experiment's shape — 2×2 matrix, fixture set, decision rule, pre-registration
discipline, output artifacts — is committed in
[`filters.md` § Experiment design](filters.md#experiment-design). The *outcome*
(which cell wins) is unknown by construction. The *design* is not an open question.

Phase-1 behavior for the `filters:` parameter (accept, raise `NotImplementedError` on
non-nil) is documented in [`filters.md` § Phase-1 behavior](filters.md#phase-1-behavior).

## Locked threads (pointer only)

| Thread                                  | Status | Primary doc                                                      |
| --------------------------------------- | ------ | ---------------------------------------------------------------- |
| Descriptor, Field, Callable contract    | Locked | [descriptor.md](descriptor.md), [errors.md](errors.md)           |
| Compile, Composition, record-access     | Locked | [compilation.md](compilation.md), [config.md](config.md)         |
| Output Modes, Writer lifecycle          | Locked | [output-modes.md](output-modes.md), [generated-class.md](generated-class.md) |
| Public API, gem layout, internal layers | Locked | [structure.md](structure.md)                                     |
| Dump, Environment contract              | Locked | [dumping.md](dumping.md)                                         |
| Code Builder, backtrace strategy        | Locked | [code-generation.md](code-generation.md)                         |
| Testing strategy + feature-test matrix  | Locked | [testing.md](testing.md)                                         |
| CI matrix, Appraisal, lint, lefthook    | Locked | [ci.md](ci.md)                                                   |
| Benchmark harness + scenario layout     | Locked | [benchmarks.md](benchmarks.md)                                   |
| Filter public shape + experiment design | Locked | [filters.md](filters.md)                                         |
| Phasing + phase-1 bar                   | Locked | [goals.md § Phasing](goals.md#phasing), [phase-1-bar.md](phase-1-bar.md) |
