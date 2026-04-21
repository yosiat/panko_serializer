# Open questions

Design threads not yet resolved. Each one has a rough shape proposed but awaits
confirmation. Record-access strategy is no longer in this list — it's fully resolved
across [compilation.md](compilation.md), [config.md](config.md), and the research notes
in [research/](research/). The only remaining sub-thread from that area:

- **Generic-path fallback when a Record is neither a Hash nor responds to the Source
  method.** Current lean: let it raise `NoMethodError` naturally; the backtrace points at
  the emitted line. Confirm or design a friendlier error.

## Filters

The feature is specified ("Give option to filter — include or exclude — deeply nested
serializers") but the shape isn't designed. Key questions:

- **Shape of the filter value.** Flat Arrays (`only: [:id, :title]`) vs nested hashes
  (`{ posts: { only: [:id, :title], comments: { only: [:body] } } }`) vs a dedicated
  **Filter** class.
- **Resolution**: applied at the **Generated Class** level, threaded down through
  **Composition**.
- **Interaction with `if:` conditions on Associations.** Does a filter overriding a field
  bypass `if:` evaluation? (Probably yes for skipped fields — cheaper not to evaluate.)
- **Perf cost**: filters add a branch per potentially-filtered node. Should there be a
  compile-time knob to disable filter support for **Descriptors** that never need it
  (zero overhead)?
- **Filters in Hash mode vs JSON mode**: identical semantics, different code paths.

## Context

- **Type**: currently spec'd as "arbitrary data." Is there a type constraint? Probably not
  — arbitrary is fine.
- **Nilability**: `context:` defaults to `nil`. Is there a case where a **Callable**
  requires it? Probably yes, but that's the consumer's contract — library passes through
  whatever was supplied.
- **Filter-in-context**: should filters also be accessible via context, or are they a
  separate concern? Current design: separate. Clear semantic boundary.

## Hash-mode key format

[config.md](config.md) proposes `hash_key_type: :string | :symbol` as a potential config
flag. Unresolved:

- Default: string (matches Panko and JSON round-tripping).
- If symbol mode is added, are keys frozen symbols or regular? Frozen, always.
- Does it affect only top-level output keys, or also nested **Association** output keys?
  Should be uniform.

## Public API namespace & gem structure

- Top-level module: `SerializersCodeGen` (tentative).
- Gem name (internal only, not published): matches the module name.
- Directory layout (standard Ruby gem): `lib/serializers_code_gen/...` with one file per
  major type.
- Whether `SerializersCodeGen.compile` lives on the top-level module or `SerializersCodeGen::Compiler`.
  Top-level module as a facade is friendlier.

## Testing strategy

- RSpec confirmed.
- **Feature tests (end-to-end)**: exercise a **Compile** + `serialize_one` / `serialize_many`
  against fixture data. Fixture **Records** should cover AR models and Hashes.
- **Unit tests via snapshots**: snapshot the generated source for fixture **Descriptors**.
  Library to use? `rspec-snapshot`, `rspec-json_expectations`, or hand-rolled against files.
  Decision pending.
- **Snapshot scope**: per-emitter-method output snapshots vs per-full-class output snapshots.
  Probably both — emitter-level for quick unit tests, full-class for integration.

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

- GitHub Actions matrix: Ruby 3.4.x × 4.0.x × Rails 7.2 × 8.0 × 8.1.
- Steps: lint (rubocop?), type check (sorbet/steep? — probably not), tests, benchmarks.
- Decision: should benchmark failures block merge, or just report?

## Ruby / Rails support matrix structure

The code should be structured so that dropping a Rails version is mechanical — say, one
adapter file per version with a shared interface. Sketch:

```
lib/serializers_code_gen/ar_adapter/
  rails_7_2.rb
  rails_8_0.rb
  rails_8_1.rb
  base.rb          # the interface
  current.rb       # picks the right adapter based on Rails.version
```

Exact shape TBD.

## Descriptor validation

When is a **Descriptor** validated? Proposals:

- Eagerly at `Data.new` time (via `Data.define` custom `initialize`).
- Lazily at **Compile** time (one pass before emitting).
- Both: structural validation eagerly, semantic validation at **Compile** time.

Current lean: both. Structural (types, enums) eager; semantic (name uniqueness across
**Attributes** and **Associations**, **Callable** arity, etc.) at **Compile**.
