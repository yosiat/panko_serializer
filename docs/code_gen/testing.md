# Testing strategy

How the library is tested. Terms in bold are defined in
[../UBIQUITOUS_LANGUAGE.md](../UBIQUITOUS_LANGUAGE.md).

## Framework

RSpec. Tests follow **Arrange-Act-Assert**; arrange must be minimal. If repeated
fixture-building code starts dominating a spec, extract to a support helper (e.g.,
`spec/support/fixture_builders.rb`) — not FactoryBot. The "few lines of setup" shape is
part of the test's readability.

## Test tiers

Five tiers, ordered by abstraction level:

| Tier                    | What it tests                                                           | Where it lives                      |
| ----------------------- | ----------------------------------------------------------------------- | ----------------------------------- |
| **CodeBuilder**         | Pure string/indent accumulator. No domain types.                        | `spec/code_builder_spec.rb`         |
| **Validators**          | Behavior of each validation rule; error hierarchy.                      | `spec/validators/*_spec.rb`         |
| **Snapshot**            | **Generator** / **Dump** byte-emit matches committed fixture `.rb` files. | `spec/generators/snapshot_spec.rb`  |
| **Feature**             | End-to-end serialization behavior against records.                      | `spec/features/*_spec.rb`           |
| **Compile-time errors** | `DescriptorError`, `CompileError` subclasses surface correctly.         | `spec/compile_errors_spec.rb`       |

### What we deliberately are not doing

- **No per-emitter snapshot tests.** Full-class snapshots cover the same ground with less
  brittleness. Per-emitter snapshots amplify change-churn (a whitespace tweak breaks 20
  files) and pin implementation, not behavior.
- **No grep-style structural assertions on emitted source.** `expect(source).to include("_read_attribute")`
  fails on "different" not "broken"; it pins implementation, not behavior. Where emit
  choice has an observable behavioral consequence — e.g., the specialized path bypasses
  reader overrides — test that behavior directly. Where it doesn't, the full-class
  snapshot is the only honest place to pin it.

## Snapshot infrastructure

### Mechanism: hand-rolled

Hand-rolled custom matcher, not `rspec-snapshot`. Rationale: the snapshot artifacts are
**shipped Ruby source** — runnable `.rb` files produced by **Dump**. The contract requires
them byte-identical to what **Compiler** feeds to `module_eval`. Storing them as committed
`.rb` files (rather than `rspec-snapshot`'s `.snap` blobs) gives:

- PR reviewers read real Ruby, not opaque snapshot framing.
- One source of truth: the snapshot file *is* the **Dump** output.
- **Dump**-output verification and **Generator**-output verification become the same
  assertion.

### Matcher API

```ruby
expect(actual_source).to match_snapshot("shallow_generic_json.rb")
```

~30 lines in `spec/support/snapshot_matcher.rb`. Mismatches delegate formatting to
`RSpec::Expectations.differ` for multi-line diff output.

### Disk layout

```
spec/
  fixtures/
    descriptors/              # Ruby modules — each exports DESCRIPTOR, CONFIG, MODES,
      shallow_generic.rb      # sanity_record, expected_output(mode)
      shallow_specialized.rb
      ...
      all.rb                  # aggregates → FIXTURES array
    generated/                # snapshot files — each is a runnable Generated Class
      shallow_generic_json.rb
      shallow_generic_hash.rb
      ...
  generators/
    snapshot_spec.rb          # iterates FIXTURES × MODES
  features/
    shallow_generic_spec.rb   # compiles fresh, never loads snapshots
    ...
  support/
    snapshot_matcher.rb
    schema.rb
    models.rb
```

`spec/spec_helper.rb` unshifts `spec/fixtures/generated` and `spec/fixtures/descriptors`
onto `$LOAD_PATH`, so specs use `require "shallow_generic_json"` instead of path-relative
requires. Decouples spec-file location from fixture location.

### Update workflow

Strict: fail on missing. Two write modes for creation/regeneration:

| Env var                       | Behavior                                              | Rake wrapper                    |
| ----------------------------- | ----------------------------------------------------- | ------------------------------- |
| *(unset)*                     | Compare only. Fail on missing, fail on diff.          | `rake spec`                     |
| `UPDATE_SNAPSHOTS=missing`    | Write missing files. **Never overwrites existing.**   | `rake snapshots:create_missing` |
| `UPDATE_SNAPSHOTS=1`          | Write missing + overwrite existing diffs.             | `rake snapshots:update_all`     |

The `missing` mode preserves the "review the diff on PR" discipline when adding a new
fixture: the snapshot for the new fixture can be created, but an unrelated emitter drift
in the same branch can't be silently absorbed.

Auto-creation without the env var is explicitly rejected — it's how snapshot tests rot
(first run silently commits garbage, test becomes self-fulfilling).

Orphan detection (snapshot files with no corresponding spec) is deferred. Add a rake lint
task if it becomes a problem.

### Three tests per (fixture, mode)

For each fixture and each of its **Output Modes**:

1. **Generator emit matches snapshot** — `Generator#emit` produces bytes equal to the
   on-disk `.rb` file.
2. **Dump write matches snapshot** — `SerializersCodeGen.dump(...)` writes a file whose
   bytes equal the snapshot.
3. **Snapshot file loads and runs** — `require` the snapshot file, instantiate the
   **Generated Class**, pass a hardcoded `sanity_record`, compare output to a hardcoded
   `expected_output`.

Together, (1) and (2) mechanically verify the **Compiler ≡ Dump byte-identical** contract
— both materialization paths hit the same on-disk artifact; divergence breaks a test. (3)
prevents regressions where the committed snapshot is bytes that no longer form valid
Ruby, or silently drops a field.

No separate parity spec is needed.

## Canonical snapshot corpus

Ten fixtures. Each compiled in the relevant **Output Modes**, yielding ~16 snapshot files.

### Core emit-shape fixtures (both `:json` and `:hash`)

| # | Name                  | Shape                                                                                                                                | Pins                                                                                                 |
| - | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| 1 | `shallow_generic`     | `Models: nil`, 3 Attributes                                                                                                          | Generic-path dispatch, `_write_one_hash` + `_write_one_object`, default string-key Hash lookup.     |
| 2 | `shallow_specialized` | `Models: [Post]`. 2 column-backed Attributes, 1 method-dispatched Attribute (reader override). MethodAttributes arity 0, 1 (SKIP), 2. | Specialized classification, arity-specialized emit, SKIP identity-compare, Callable ivar hoisting.  |
| 3 | `nested_composition`  | Post → `has_one :author`, `has_many :comments`. Author with `if: ->(r, c) { ... }`.                                                  | Composition constructor wiring, default `null_for_missing_has_one: true` emit, has_many iteration, Association-`if:` emit, filter threading. |
| 4 | `recursive_self`      | Comment with `has_many :replies` → same Comment Descriptor.                                                                          | Self-ref short-circuit: `@replies_serializer = self`.                                                |
| 5 | `recursive_mutual`    | Folder → Item → Folder cycle.                                                                                                        | Identity-cache threading at construction — one instance per unique Descriptor in the cycle.          |
| 6 | `sti_specialized`     | `Models: [Vehicle, Car]`, `Car < Vehicle`. Car overrides a column reader. 2 Attributes: one uniformly column-backed; one downgraded to method dispatch due to override. | STI intersection classification.                                                                     |

### Config-isolation fixtures

One config field flipped per fixture; each owns a minimal dedicated **Descriptor** not
shared with #1–#6, so core-fixture churn doesn't cascade into config snapshots.

| #  | Name                            | Descriptor                                                             | Config flip                       | Mode  | Pins                                            |
| -- | ------------------------------- | ---------------------------------------------------------------------- | --------------------------------- | ----- | ----------------------------------------------- |
| 7  | `config_root_key_on`            | `Models: nil`, 1 Attribute                                             | `supports_root_key: true`         | JSON  | `root_key:` kwarg + wrap emit.                  |
| 8  | `config_null_for_has_one_off`   | `Models: nil`, 1 Attribute, 1 `has_one` to a minimal inner Descriptor  | `null_for_missing_has_one: false` | JSON  | Omit-key-when-nil branch of has_one emit.       |
| 9  | `config_hash_record_key_symbol` | `Models: nil`, 2 Attributes                                            | `hash_record_key_type: :symbol`   | JSON  | Symbol-key Hash lookup in `_write_one_hash`.    |
| 10 | `config_hash_output_key_symbol` | `Models: nil`, 2 Attributes                                            | `hash_output_key_type: :symbol`   | Hash  | Symbol-key output emit in Hash mode.            |

### Fixture module shape

```ruby
# spec/fixtures/descriptors/shallow_generic.rb
module Fixtures
  module ShallowGeneric
    CONFIG     = SerializersCodeGen::Config.new
    DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ShallowGenericSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id,    source: :id),
        SerializersCodeGen::Attribute.new(name: :title, source: :title),
      ],
      method_attributes: [],
      associations: [],
    )
    MODES = %i[json hash]

    def self.sanity_record
      {"id" => 1, "title" => "hi"}
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"id":1,"title":"hi"}'
      when :hash then {"id" => 1, "title" => "hi"}
      end
    end
  end
end
```

Each fixture's `Descriptor#name` must be globally unique — the snapshot tier requires the
file, so every **Generated Class** name (`ShallowGenericSerializer_JSON`) lands in the
top-level namespace. Convention-enforced; collisions break loudly at load time.

## Feature-test environment

### Real ActiveRecord + in-memory sqlite

```ruby
# spec/spec_helper.rb
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
require "schema"
require "models"
```

Rationale:

- The library depends on real AR semantics — `_read_attribute`, `columns_hash`,
  `define_attribute_methods`. Mocking AR would reintroduce the bug class that
  [research/](research/) was specifically written to avoid.
- sqlite-in-memory is zero-config, fast everywhere CI runs, and the library doesn't test
  SQL semantics — it tests AR-object-access.

**Future: DB matrix in CI.** A matrix run across mysql/postgres adapters may be added to
verify `_read_attribute` behavior across DBs. Not v1. When added, schema definitions stay
portable or the schema file gates per-adapter.

### Schema and model classes

- `spec/support/schema.rb` — single `ActiveRecord::Schema.define` block for all tables.
- `spec/support/models.rb` — all AR classes (`Post`, `Comment`, `Author`, `Vehicle`,
  `Car`, `Folder`, `Item`).

### Isolation: transactional rollback per test

```ruby
config.around(:each) do |example|
  ActiveRecord::Base.transaction do
    example.run
    raise ActiveRecord::Rollback
  end
end
```

No DatabaseCleaner dependency. `use_transactional_fixtures` pattern, without Rails.

### Fixture data creation: inline `create!`, no FactoryBot

- Small number of model classes, few columns each.
- Inline data keeps tests self-documenting — the test shows exactly what it serializes.
- No extra dependency.

**Minimal-arrange principle.** If repeated arrange blocks start dominating feature specs,
extract to `spec/support/fixture_builders.rb` (or similar utility module) — not
FactoryBot. The AAA flow expects arrange to be brief; when it isn't, the pressure is
toward helper extraction, not tooling replacement.

### Record-shape coverage

Only fixtures with `Models: nil` exercise non-AR records — the specialized path contract
assumes **Records** are AR instances of declared classes.

| Fixture family                         | Record shapes exercised in features            |
| -------------------------------------- | ---------------------------------------------- |
| Specialized (#2, #3 w/ AR assocs, #6)  | AR instances only                              |
| Generic (#1, #7, #8, #10)              | Hash (string keys) + PORO via `Struct`         |
| Generic + symbol config (#9)           | Hash (symbol keys) + PORO via `Struct`         |

PORO coverage uses `Struct.new(...).new(...)` — the minimum-viable record that responds
only to the named methods. Proves no hidden AR-ness dependency on the generic path.

## Recursion tests

Finite data, hand-built. The library contract (see [compilation.md](compilation.md)) is
"caller keeps the **Record** graph acyclic." Runtime cycle detection is explicitly out of
scope.

### `recursive_self`

3-node Comment tree; leaves have empty `replies`:

```ruby
root = Comment.create!(body: "root")
Comment.create!(body: "c1", parent_comment: root)
Comment.create!(body: "c2", parent_comment: root)
# c1 and c2 have no further replies → natural termination
```

### `recursive_mutual`

`Folder → Item → Folder` cycle, 2-deep sample data:

```ruby
inner = Folder.create!(name: "inner")          # no items
root  = Folder.create!(name: "root")
Item.create!(folder: root, subfolder: inner)
# inner has no items → natural termination
```

## Not tested

- **Runtime infinite cycles on the record graph.** The contract is "caller guarantees
  acyclic data." Testing "Ruby's stack overflows" is testing Ruby, not our library. If
  Ruby's stack semantics changed, we wouldn't want to fail — and marking it as our spec
  would imply we'd stabilize it, which we wouldn't. Documented as contract; no spec.
- **Thread-safety under concurrent serialization.** Deferred. The design pins state to
  method parameters and frozen ivars (see [generated-class.md](generated-class.md)); ad-hoc
  stress testing will be flaky. Add if a concrete regression motivates it.
- **Cross-version Rails adapter differences at unit level.** The CI matrix (Ruby 3.4.x ×
  4.0.x × Rails 7.2 / 8.0 / 8.1) runs the entire test suite against every combination —
  the matrix itself is the adapter verification; no dedicated per-version specs.

## Open testing threads

Not decided yet — queued for later in the design session:

- **Feature-test coverage matrix for cross-cutting concerns.** Filter shapes
  (`only:` / `except:` / nested / empty), `SKIP`, `if:` short-circuit behavior,
  `root_key:` wrapping, error-path specs. The fixture set is locked above; what remains
  is the per-feature test volume and organization (shared examples vs per-fixture
  specs).
- **Benchmark harness.** See [open-questions.md](open-questions.md) — benchmark-ips +
  memory_profiler, target comparisons, regression guard.
