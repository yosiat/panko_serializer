# Benchmarks

Performance measurement strategy — harness, scenarios, comparison targets, and
regression workflow. Terms in bold are defined in
[../UBIQUITOUS_LANGUAGE.md](../UBIQUITOUS_LANGUAGE.md).

Benchmarks **do not run in CI** (see [ci.md § Benchmarks in CI](ci.md#benchmarks-in-ci)).
They run on dev hardware against a committed baseline in release notes. Refinement of
the structure below is expected once the harness lands — this doc captures the locked
structural decisions, not a final spec.

## Harness

`benchmark-ips` + `memory_profiler`, combined **in a single block per measurement**
(a `benchmark(label) { ... }` call produces ips + allocs + retained in one row).
Lifted and adapted from
[Panko's existing benchmark harness](https://github.com/yosiat/panko_serializer/blob/master/benchmarks/support/benchmark.rb).

### Core features carried over

- `benchmark(label, &block)` — one row of output; ips + allocs + retained measured on
  the same block.
- `benchmark_with_records(label, type:, &block)` — iterates configured sizes,
  automatically slices the dataset.
- **Env knobs**:
  - `SIZE=n` — run a single size instead of the default list.
  - `BENCH=<substr>` — filter benchmarks by case-insensitive label substring.
  - `PROFILE=cpu|memory` — swap modes; `cpu` collects a StackProf run at exit, `memory`
    pretty-prints a MemoryProfiler report.
  - `IPS_TIME` / `IPS_WARMUP` — tune benchmark-ips parameters.
- `RubyVM::YJIT.enable` auto-enabled if present.
- GC disabled around the measurement block; re-enabled after.
- Output is stdout-only — no persisted baseline files (see [Baseline workflow](#baseline-workflow)).

## Directory layout — scenario-centric

Structured **per scenario**, not per comparison target. Each scenario file contains
all target implementations side-by-side so the stdout table is a cross-target
comparison in a single run.

```
benchmarks/
  # Sanity scenarios (cover basic shapes, mirror Panko's existing scenarios)
  simple.rb                      # flat Attributes
  has_one.rb                     # single has_one Association
  has_many.rb                    # has_many Association
  method_attribute.rb            # Method Attribute
  aliases.rb                     # Attribute name ≠ source
  json_column.rb                 # Attribute backed by a JSON DB column
  filter_only.rb                 # Filter only:
  filter_except.rb               # Filter except:

  # Beyond-sanity scenarios (shapes Panko's current bench suite lacks)
  wide_attributes.rb             # ~70 Attributes — stresses per-Field emit/dispatch cost
  graph.rb                       # entrypoint Descriptor with Attributes + multiple has_one
                                 # + multiple has_many — stresses combined Composition

  # serializers_code_gen-specific scenarios
  # (only compare scg variants against each other; no cross-target row)
  scg_generic_vs_specialized.rb  # Models: nil vs Models: [Post], same shape
  scg_skip_elision.rb            # MethodAttribute returning SKIP on half the records
  scg_recursive.rb               # Comment self-ref, 3 levels deep (recursive_self shape)

  support/
    benchmark.rb                 # harness core
    datasets.rb                  # AR in-memory sqlite seeding (posts, authors, comments, …)
    setup.rb                     # env + AR setup + YJIT auto-enable
    targets.rb                   # target-callable registry
```

### Why scenario-centric and not target-centric

Panko's current layout is **one file per comparison target** (`panko_json.rb`,
`panko_object.rb`, `plain_object.rb`) with the same scenarios defined inside each.
That shape has two problems:

1. **Cross-target comparison requires reading N tables** from N separate runs and
   transposing mentally. The question users actually ask ("how does
   serializers_code_gen compare to panko on HasMany?") is the *hard* one to answer.
2. **Adding a scenario edits N files**, one per target.

Scenario-centric inverts both: one file per scenario, all targets as rows inside.
Adding a scenario = one new file. Adding a target = one entry in `support/targets.rb`.
Never both, never N-way.

## Comparison targets

Three families for v1, six rows per sanity scenario:

| Row label                           | Implementation                                       |
| ----------------------------------- | ---------------------------------------------------- |
| `serializers_code_gen/json`         | This library, `:json` **Output Mode**.               |
| `serializers_code_gen/hash`         | This library, `:hash` **Output Mode**.               |
| `panko/json`                        | Current Panko, `.to_json`.                           |
| `panko/object`                      | Current Panko, object-mode.                          |
| `plain/json`                        | `records.map(&:as_json).to_json`.                    |
| `plain/hash`                        | `records.map(&:as_json)`.                            |

**No ActiveModel::Serializers.** AMS is absent from Panko's current benchmark suite,
not a target this library competes against, and its shape differs enough from the
others that fair comparison is hard.

**Oj-Serializers is future work.** When added, it's a single entry in
`support/targets.rb` plus one row per scenario file — no structural change.

### Fresh serializer definitions, not shared with Panko's existing benchmarks

Benchmark serializers are **purpose-built for this library's benchmark suite**, not
lifted from Panko's `benchmarks/panko_json.rb`. Two reasons:

1. **Shape parity matters.** The `panko/json` row must express the same semantic
   scenario as the `serializers_code_gen/json` row. Reusing Panko's existing
   `PostFastSerializer` would leave us benchmarking subtly different shapes.
2. **Panko's existing bench coverage is missing cases we care about** — specifically
   the wide-attribute and graph scenarios listed above. Building our own serializer
   set lets us match the scenario list exactly.

## Scenario file shape

Each scenario file requires the harness + targets registry, then declares the
cross-target row set:

```ruby
# benchmarks/has_many.rb
require_relative "support/benchmark"
require_relative "support/targets"

benchmark_scenario "HasMany", type: :authors do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:has_many].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:has_many].call(records) },
    "panko/json"                => -> { Targets::PANKO_JSON[:has_many].call(records) },
    "panko/object"              => -> { Targets::PANKO_OBJECT[:has_many].call(records) },
    "plain/json"                => -> { Targets::PLAIN_JSON[:has_many].call(records) },
    "plain/hash"                => -> { Targets::PLAIN_HASH[:has_many].call(records) },
  }
end
```

**Skipping a row** when a target can't express a scenario (e.g., `plain` for filter
scenarios): omit the entry and note `# n/a — plain has no filter primitive` in a
comment above the hash. Row set shape is per-scenario, not required to be identical.

## Running

- **One scenario**: `bundle exec ruby benchmarks/has_many.rb`.
- **All scenarios**: `rake bench:all` — globs `benchmarks/*.rb` (excluding `support/`)
  and executes each in sequence. Stdout tables stack.
- **Env filtering**: `SIZE=50`, `BENCH=HasMany`, `TARGET=panko_json` all pass through
  the harness and filter per row.

## Baseline workflow

No persisted baseline files. **Numbers live in release notes** — when a perf-relevant
change lands, the PR author copies the before/after tables into the PR description and
(on release) into the release notes.

For the **benchmark-gated experiments** (filter dual-path emit, filter internal rep —
see [filters.md](filters.md)), follow the `docs/research/` template: commit the
experiment-specific bench script + a markdown report with numbers and the decision.
Example to match: `docs/research/ar_access_bench.rb` + `docs/research/ar_access_results.md`.

## Fixture data

`benchmarks/support/datasets.rb` seeds posts / authors / comments in in-memory sqlite
— same table shapes as `spec/support/schema.rb`, but a **separate file**. Specs and
benchmarks have different data-creation needs (specs want inline `create!` per test;
benchmarks want bulk pre-seeded datasets via `DATASETS` registry), so we don't share
the setup file.

Sizes: `BENCHMARK_SIZES = [50, 2300]` — matches Panko's current sizes, keeps scale
numbers comparable with existing Panko runs over time.

## Open refinements

These aspects are likely to evolve once the harness lands:

- Scenario names and exact shapes — may grow/shrink as implementation reveals hot
  paths worth isolating.
- Whether `wide_attributes` should cover a second dimension (attr count `×` record
  count), or stay one-dimensional.
- Whether `graph.rb` is one shape or several (e.g., "narrow entrypoint, wide children"
  vs. "wide entrypoint, narrow children").
- Record-shape coverage in benchmarks: AR-only for now (the hot path). Adding
  Hash/PORO benchmark rows to scg scripts is deferred until a specific question
  motivates it.
