# Open questions

Design threads not yet resolved. Everything else — descriptor, compilation, composition,
record-access, testing strategy, CI, benchmarks harness — is locked in the corresponding
doc under [`docs/`](README.md). Before adding anything here, check [`deferred.md`](deferred.md)
to be sure a topic isn't deliberately punted.

## Filter experiments — benchmark-gated at implementation time

Public **Filter** shape is locked in [filters.md](filters.md) — nested Hash matching
Panko's current format, `:only` / `:except` / child-key semantics, threading rules,
filter-before-`if:` short-circuit. What remains are two implementation choices that
interact and will be resolved together via a benchmark run following the
[`docs/research/`](research/) template:

- **Dual-path emit** — single filter-aware path vs. `_write_one_unfiltered` +
  `_write_one_filtered` per **Generated Class** with a one-branch dispatcher at
  `_write_one`. Trade: optimal unfiltered body vs. ~2× method bodies per class.
  See [filters.md § Dual-path emit](filters.md#dual-path-emit--experiment-driven).
- **Internal representation of the Filter object** — thin Hash wrapper
  (`Array#include?` per check) vs. pre-normalized per-level index (`Set` per level +
  cached child Filter objects). Trade: allocation cost up front vs. O(n) lookup per
  check. See [filters.md § Internal representation](filters.md#internal-representation--experiment-driven).

The two interact — Set-index makes the filter-aware path cheap, which shrinks
dual-path's benefit; Hash-wrapper makes it expensive, which grows dual-path's benefit.
Evaluating either in isolation assumes the other is fixed, which we don't have grounds
to do.

### JSON/Hash parity

Semantics identical across **Output Modes**; emit paths differ. Documented in
[filters.md § JSON vs Hash output parity](filters.md#json-vs-hash-output-parity).
Confirm at implementation time — no open decision, just a test-tier claim.

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
