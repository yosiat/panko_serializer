# Benchmarks

Performance measurement strategy: harness, scenarios, comparison targets, and
regression workflow. Terms in bold are defined in
[UBIQUITOUS_LANGUAGE.md](UBIQUITOUS_LANGUAGE.md).

Benchmarks **do not run in CI**: GitHub Actions' noise floor exceeds the signal we
care about. They run on dev hardware against a committed baseline in release notes.

## Harness

`benchmark-ips` + `memory_profiler`, combined **in a single block per measurement**
(a `benchmark(label) { ... }` call produces ips + allocs + retained in one row). The
harness is `benchmarks/support/benchmark.rb`.

### Core features

- `benchmark(label, &block)`: one row of output; ips + allocs + retained measured on
  the same block.
- **Env knobs**:
  - `SIZE=n`: run a single size instead of the default list.
  - `BENCH=<substr>`: filter benchmarks by case-insensitive label substring.
  - `PROFILE=cpu|memory`: swap modes; `cpu` collects a StackProf run at exit, `memory`
    pretty-prints a MemoryProfiler report.
  - `IPS_TIME` / `IPS_WARMUP`: tune benchmark-ips parameters.
- `RubyVM::YJIT.enable` auto-enabled if present.
- GC disabled around the measurement block; re-enabled after.
- Output is stdout-only: no persisted baseline files (see [Baseline workflow](#baseline-workflow)).

## Directory layout: scenario-centric

Structured **per scenario**, not per comparison target. Each scenario file contains
all target implementations side-by-side so the stdout table is a cross-target
comparison in a single run.

```
benchmarks/
  # Sanity scenarios (basic shapes)
  simple.rb                      # flat Attributes
  has_one.rb                     # single has_one Association
  has_many.rb                    # has_many Association
  method_attribute.rb            # Method Attribute
  aliases.rb                     # Attribute name ≠ source
  json_column.rb                 # Attribute backed by a JSON DB column
  datetimes.rb                   # datetime columns: raw-string emit fast path
  filter_only.rb                 # Filter only:
  filter_except.rb               # Filter except:
  filter_build.rb                # Filter.wrap construction cost, isolated from emit

  # Beyond-sanity scenarios
  wide_attributes.rb             # ~70 Attributes: stresses per-Field emit/dispatch cost
  graph.rb                       # entrypoint Descriptor with Attributes + multiple has_one
                                 # + multiple has_many: stresses combined Composition
  medium_graph_shallow_only.rb   # 8-field entrypoint under only:, the filter verdict-cell shape
  single_record.rb               # one-record APIs (`serialize_one`, `Serializer.one`,
                                 # `record.as_json`) on a Bench::Post + author + comments
                                 # graph; carries an output-parity guard at the top of the
                                 # file (Oj.load(mode: :strict) on every row's JSON; abort
                                 # with a labeled diff if any row diverges): future
                                 # scenarios should mirror this guard

  # Cross-library comparison
  game_serializer.rb             # single + collection Game/Player graph across panko,
                                 # oj_serializers, alba, blueprinter, and plain Oj /
                                 # as_json baselines: gated on byte-identical output

  # engine-only scenarios (compare engine variants against each other; a panko/*
  # row, where present, measures the DSL/runtime-seam overhead over the engine)
  children_from_models.rb              # children reached through a plain method; the child
                                       # serializer's `models` picks generic / specialized / variants
  code_gen_generic_vs_specialized.rb  # model: nil vs model: Bench::Post, same shape
  code_gen_skip_elision.rb            # MethodAttribute returning SKIP on half the records
  code_gen_recursive.rb               # Comment self-ref, 3 levels deep (recursive_self shape)

  # Memory check (not a speed benchmark)
  writer_retention.rb                  # RSS held by pooled JSON writers across long-lived threads;
                                       # Linux only (reads /proc), run it directly, not via rake

  support/
    benchmark.rb                 # harness core
    datasets.rb                  # AR in-memory sqlite seeding (posts, authors, comments, …)
    setup.rb                     # env + AR setup + YJIT auto-enable
    targets.rb                   # target-callable registry
```

### Why scenario-centric and not target-centric

One file per scenario, all targets as rows inside, so one stdout table answers "how does
code_gen compare to panko on HasMany?" in a single run. Adding a scenario is one new file;
adding a target is one entry in `support/targets.rb`. Never both, never N-way.

## Comparison targets

Four families, seven rows per sanity scenario (`graph.rb` adds two `[with-only]` engine rows):

| Row label                           | Implementation                                       |
| ----------------------------------- | ---------------------------------------------------- |
| `code_gen/json`         | The engine (`Panko::CodeGen`) directly, `:json` **Output Mode**. |
| `code_gen/hash`         | The engine directly, `:hash` **Output Mode**.        |
| `panko/json`                        | Panko's public DSL, `ArraySerializer#to_json`.      |
| `panko/object`                      | Panko's public DSL, object/Hash mode (`#to_a`).     |
| `oj_serializers/json`               | Oj-Serializers gem, JSON output.                     |
| `plain/json`                        | `records.map(&:as_json).to_json`.                    |
| `plain/hash`                        | `records.map(&:as_json)`.                            |

The `panko/*` rows drive Panko's public DSL and runtime seam, so the gap to the raw
`code_gen/*` rows is the overhead the seam adds over the engine. The
`oj_serializers/json` row is the external competitive reference (measured and recorded,
non-blocking). Plain rows are context, not competitive targets.

**No ActiveModel::Serializers.** Its shape differs enough from the others that a fair
comparison is hard.

### Cross-library comparison: `game_serializer.rb`

The per-shape scenarios above compare the engine against the `panko/*`, `oj_serializers`,
and `plain` rows. `benchmarks/game_serializer.rb` is the broader cross-library bench: a
single Game/Player graph run in both single-record and collection form across Panko,
Oj-Serializers, Alba, Blueprinter, and plain Oj / `as_json` baselines. Every row is
gated on **byte-identical output**: the file aborts before measuring if any target's
emit shape diverges from the reference: so the numbers compare like for like. It runs
under `rake benchmarks:all` alongside the scenario files but stands on its own; treat it
as the head-to-head across the wider serializer ecosystem, not as a shape scenario.

### Purpose-built serializers per scenario

Each scenario file defines all its target serializers inline, purpose-built to express
one shape across every row. Two reasons:

1. **Shape parity matters.** The `panko/json` row must express the same semantic
   scenario as the `code_gen/json` row; defining both from the same field
   list in one file keeps them from drifting into subtly different shapes.
2. **The scenario list drives coverage**: including the wide-attribute and graph
   shapes above. Owning the serializer set
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
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:has_many].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:has_many].call(records) },
    "panko/json"                => -> { Targets::PANKO_JSON[:has_many].call(records) },
    "panko/object"              => -> { Targets::PANKO_OBJECT[:has_many].call(records) },
    "oj_serializers/json"       => -> { Targets::OJ_JSON[:has_many].call(records) },
    "plain/json"                => -> { Targets::PLAIN_JSON[:has_many].call(records) },
    "plain/hash"                => -> { Targets::PLAIN_HASH[:has_many].call(records) },
  }
end
```

**Skipping a row** when a target can't express a scenario (e.g., `plain` for filter
scenarios): omit the entry and note `# n/a: plain has no filter primitive` in a
comment above the hash. Row set shape is per-scenario, not required to be identical.

## Running

- **One scenario**: `bundle exec ruby benchmarks/has_many.rb`, or
  `rake benchmarks:run[has_many]`.
- **All scenarios**: `rake benchmarks:all`: globs `benchmarks/*.rb` and executes each
  in sequence. Stdout tables stack. `writer_retention.rb` is Linux-only and aborts
  elsewhere.
- **Env filtering**: `SIZE=50`, `BENCH=HasMany`, `TARGET=panko/json` all pass through
  the harness. `TARGET` is a case-insensitive substring of the row label (`code_gen/json`,
  `panko/object`, ...), so `TARGET=panko/` keeps both Panko rows.

## Baseline workflow

No persisted baseline files. **Numbers live in release notes**: when a perf-relevant
change lands, the PR author copies the before/after tables into the PR description and
(on release) into the release notes.

## Fixture data

`benchmarks/support/datasets.rb` seeds posts / authors / comments in in-memory sqlite,
with table shapes like `spec/code_gen/support/schema.rb` but in a **separate file**. Specs and
benchmarks have different data-creation needs (specs want inline `create!` per test;
benchmarks want bulk pre-seeded datasets via `DATASETS` registry), so we don't share
the setup file.

Sizes: `BENCHMARK_SIZES = [50, 2300]`, which keeps scale numbers comparable across runs
over time.

## Open refinements

These aspects may still evolve as the suite grows:

- Scenario names and exact shapes: may grow/shrink as profiling reveals hot paths
  worth isolating.
- Whether `wide_attributes` should cover a second dimension (attr count `×` record
  count), or stay one-dimensional.
- Whether `graph.rb` is one shape or several (e.g., "narrow entrypoint, wide children"
  vs. "wide entrypoint, narrow children").
- Record-shape coverage in benchmarks: AR-only for now (the hot path). Adding
  Hash/PORO benchmark rows to engine scripts is deferred until a specific question
  motivates it.
