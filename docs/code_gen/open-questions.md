# Open questions

Design threads not yet resolved. Each one has a rough shape proposed but awaits
confirmation. Record-access strategy is fully resolved across
[compilation.md](compilation.md), [config.md](config.md), [descriptor.md](descriptor.md),
and the research notes in [research/](research/). Missing-value behavior for the generic
path (raise `NoMethodError` naturally, return `nil` for missing Hash keys) is documented
in `descriptor.md` — kept simple, no knobs. Public API surface, gem layout, and the
**Compiler** / **Generator** / **Code Builder** layering are locked in
[structure.md](structure.md). No per-Rails-version adapter code — the supported Rails
versions share a stable API; CI matrix still exercises all combinations (see CI below).
Testing strategy (framework, snapshot mechanism, canonical fixture corpus, feature-test
environment) is captured in [testing.md](testing.md); the cross-cutting feature-test
coverage matrix is the one testing thread still open.

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

Locked — see [testing.md](testing.md). Remaining sub-thread:

- **Feature-test coverage matrix for cross-cutting concerns** — filter shapes
  (`only:` / `except:` / nested / empty), `SKIP`, `if:` short-circuit behavior,
  `root_key:` wrapping, error-path specs. The fixture set, snapshot mechanism, and AR
  environment are all locked in `testing.md`; what remains is the per-feature test
  volume and organization (shared examples vs per-fixture specs).

## Benchmarks

- `benchmark-ips` for micro; `memory_profiler` for allocation tracking.
- Benchmark targets:
  - vs. Panko (current implementation)
  - vs. ActiveModel::Serializers
  - vs. plain `to_json` / `as_json`
- Benchmark fixtures: a shallow model (id + few cols), a model with **Method Attributes**,
  a model with nested **Associations**, a deep-nested model.
- Regression guard: a CI job that runs benchmarks and fails if median drops > N%.
  How to structure the baseline?

## CI

- GitHub Actions matrix: Ruby 3.4.x × 4.0.x × Rails 7.2 × 8.0 × 8.1. The matrix is the
  verification mechanism for the single-path `active_record/` code (there are no
  per-version adapters — see [structure.md](structure.md)).
- Steps: lint (rubocop?), type check (sorbet/steep? — probably not), tests, benchmarks.
- Decision: should benchmark failures block merge, or just report?
