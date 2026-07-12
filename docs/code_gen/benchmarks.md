# Benchmarks

Performance measurement strategy — harness, scenarios, comparison targets, and
regression workflow. Terms in bold are defined in
[UBIQUITOUS_LANGUAGE.md](UBIQUITOUS_LANGUAGE.md).

Benchmarks **do not run in CI** — GitHub Actions' noise floor exceeds the signal we
care about. They run on dev hardware against a committed baseline in release notes.

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
  datetimes.rb                   # datetime columns — raw-string emit fast path
  filter_only.rb                 # Filter only:
  filter_except.rb               # Filter except:
  filter_build.rb                # Filter.wrap construction cost, isolated from emit

  # Beyond-sanity scenarios (shapes Panko's current bench suite lacks)
  wide_attributes.rb             # ~70 Attributes — stresses per-Field emit/dispatch cost
  graph.rb                       # entrypoint Descriptor with Attributes + multiple has_one
                                 # + multiple has_many — stresses combined Composition
  medium_graph_shallow_only.rb   # 8-field entrypoint under only: — reproduces the filter
                                 # verdict cell from research/filter_experiments_results.md
  single_record.rb               # one-record APIs (`serialize_one`, `Serializer.one`,
                                 # `record.as_json`) on a Bench::Post + author + comments
                                 # graph; carries an output-parity guard at the top of the
                                 # file (Oj.load(mode: :strict) on every row's JSON; abort
                                 # with a labeled diff if any row diverges) — future
                                 # scenarios should mirror this guard

  # Cross-library comparison
  game_serializer.rb             # single + collection Game/Player graph across panko,
                                 # oj_serializers, alba, blueprinter, and plain Oj /
                                 # as_json baselines — gated on byte-identical output

  # engine-only scenarios (compare scg variants against each other; a panko/*
  # row, where present, measures the DSL/runtime-seam overhead over the engine)
  scg_generic_vs_specialized.rb  # model: nil vs model: Bench::Post, same shape
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

Four families, seven rows per sanity scenario:

| Row label                           | Implementation                                       |
| ----------------------------------- | ---------------------------------------------------- |
| `serializers_code_gen/json`         | The engine (`Panko::CodeGen`) directly, `:json` **Output Mode**. |
| `serializers_code_gen/hash`         | The engine directly, `:hash` **Output Mode**.        |
| `panko/json`                        | Panko's public DSL — `ArraySerializer#to_json`.      |
| `panko/object`                      | Panko's public DSL — object/Hash mode (`#to_a`).     |
| `oj_serializers/json`               | Oj-Serializers gem, JSON output.                     |
| `plain/json`                        | `records.map(&:as_json).to_json`.                    |
| `plain/hash`                        | `records.map(&:as_json)`.                            |

The `panko/*` rows drive Panko's public DSL and runtime seam, so the gap to the raw
`serializers_code_gen/*` rows is the overhead the seam adds over the engine. The
`oj_serializers/json` row is the external competitive reference (measured and recorded,
non-blocking). Plain rows are context, not competitive targets.

**No ActiveModel::Serializers.** AMS is absent from Panko's current benchmark suite,
not a target this library competes against, and its shape differs enough from the
others that fair comparison is hard.

### Cross-library comparison — `game_serializer.rb`

The per-shape scenarios above compare the engine against the `panko/*`, `oj_serializers`,
and `plain` rows. `benchmarks/game_serializer.rb` is the broader cross-library bench: a
single Game/Player graph run in both single-record and collection form across Panko,
Oj-Serializers, Alba, Blueprinter, and plain Oj / `as_json` baselines. Every row is
gated on **byte-identical output** — the file aborts before measuring if any target's
emit shape diverges from the reference — so the numbers compare like for like. It runs
under `rake benchmarks:all` alongside the scenario files but stands on its own; treat it
as the head-to-head across the wider serializer ecosystem, not as a shape scenario.

### Purpose-built serializers per scenario

Each scenario file defines all its target serializers inline, purpose-built to express
one shape across every row. Two reasons:

1. **Shape parity matters.** The `panko/json` row must express the same semantic
   scenario as the `serializers_code_gen/json` row; defining both from the same field
   list in one file keeps them from drifting into subtly different shapes.
2. **The scenario list drives coverage** — including the wide-attribute and graph
   shapes above that Panko's pre-merge bench suite lacked. Owning the serializer set
   lets each scenario match its field list exactly.

## Scenario file shape

Each scenario file requires the harness + targets registry, then declares the
cross-target row set:

```ruby
# benchmarks/has_many.rb
require_relative "support/benchmark"
require_relative "support/targets"

benchmark_scenario "HasMany", type: :posts do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:has_many].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:has_many].call(records) },
    "panko/json"                => -> { Targets::PANKO_JSON[:has_many].call(records) },
    "panko/object"              => -> { Targets::PANKO_OBJECT[:has_many].call(records) },
    "oj_serializers/json"       => -> { Targets::OJ_JSON[:has_many].call(records) },
    "plain/json"                => -> { Targets::PLAIN_JSON[:has_many].call(records) },
    "plain/hash"                => -> { Targets::PLAIN_HASH[:has_many].call(records) },
  }
end
```

**Skipping a row** when a target can't express a scenario (e.g., `plain` for filter
scenarios): omit the entry and note `# n/a — plain has no filter primitive` in a
comment above the hash. Row set shape is per-scenario, not required to be identical.

## Running

- **One scenario**: `bundle exec ruby benchmarks/has_many.rb`, or
  `rake benchmarks:run[has_many]`.
- **All scenarios**: `rake benchmarks:all` — globs `benchmarks/*.rb` and executes each
  in sequence. Stdout tables stack.
- **Env filtering**: `SIZE=50`, `BENCH=HasMany`, `TARGET=panko_json` all pass through
  the harness and filter per row.

## Baseline workflow

No persisted baseline files. **Numbers live in release notes** — when a perf-relevant
change lands, the PR author copies the before/after tables into the PR description and
(on release) into the release notes.

**Benchmark-gated decisions** that pick a representation (e.g. the filter internal rep
and dual-path emit — see [filters.md](filters.md), settled on the `Indexed` filter)
capture their evidence under [research/](research/): an experiment-specific bench
script plus a markdown report with numbers and the decision. Examples to match:
[`research/ar_access_bench.rb`](research/ar_access_bench.rb) +
[`research/ar_access_results.md`](research/ar_access_results.md), and
[`research/filter_experiments_results.md`](research/filter_experiments_results.md) for
the shipped filter verdict.

## Fixture data

`benchmarks/support/datasets.rb` seeds posts / authors / comments in in-memory sqlite
— same table shapes as `spec/support/schema.rb`, but a **separate file**. Specs and
benchmarks have different data-creation needs (specs want inline `create!` per test;
benchmarks want bulk pre-seeded datasets via `DATASETS` registry), so we don't share
the setup file.

Sizes: `BENCHMARK_SIZES = [50, 2300]` — matches Panko's current sizes, keeps scale
numbers comparable with existing Panko runs over time.

## Open refinements

These aspects may still evolve as the suite grows:

- Scenario names and exact shapes — may grow/shrink as profiling reveals hot paths
  worth isolating.
- Whether `wide_attributes` should cover a second dimension (attr count `×` record
  count), or stay one-dimensional.
- Whether `graph.rb` is one shape or several (e.g., "narrow entrypoint, wide children"
  vs. "wide entrypoint, narrow children").
- Record-shape coverage in benchmarks: AR-only for now (the hot path). Adding
  Hash/PORO benchmark rows to scg scripts is deferred until a specific question
  motivates it.
