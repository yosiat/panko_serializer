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
  spec_helper.rb
  code_builder_spec.rb                         # tier: CodeBuilder
  compile_errors_spec.rb                       # tier: compile-time errors

  validators/                                  # tier: validators
    name_uniqueness_spec.rb
    source_resolution_spec.rb
    callable_arity_spec.rb

  generators/                                  # tier: snapshot
    snapshot_spec.rb                           # iterates FIXTURES × MODES

  features/                                    # tier: feature (end-to-end)
    descriptors/                               # one file per canonical Descriptor (record-shape coverage)
      shallow_generic_spec.rb                  # compiles fresh, never loads snapshots
      shallow_specialized_spec.rb
      nested_composition_spec.rb
      recursive_self_spec.rb
      recursive_mutual_spec.rb
      sti_specialized_spec.rb
      config/                                  # config-isolation Descriptors sub-family
        root_key_on_spec.rb
        null_for_has_one_off_spec.rb
        hash_record_key_symbol_spec.rb
        hash_output_key_symbol_spec.rb
    concerns/                                  # cross-cutting behavioral specs
      filter_spec.rb                           # Filter
      skip_spec.rb                             # SKIP
      association_if_spec.rb                   # Association if: Callable short-circuit
      root_key_spec.rb                         # Root Key wrapping

  fixtures/
    descriptors/                               # Ruby modules — each exports DESCRIPTOR, CONFIG, MODES,
      shallow_generic.rb                       # sanity_record, expected_output(mode)
      shallow_specialized.rb
      ...
      all.rb                                   # aggregates → FIXTURES array
    generated/                                 # committed snapshot files — each is a runnable Generated Class
      shallow_generic_json.rb
      shallow_generic_hash.rb
      ...

  support/
    snapshot_matcher.rb
    schema.rb
    models.rb
    fixture_builders.rb                        # reserved — add only if arrange blocks start dominating
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

## Feature-test organization

Feature specs live under `spec/features/` in two parallel subtrees:

- **`spec/features/descriptors/`** — one file per canonical **Descriptor** (see
  [Canonical snapshot corpus](#canonical-snapshot-corpus) above). Each file's job is
  **record-shape coverage**: compile the fixture fresh (never load the snapshot file) and
  exercise it against the shapes listed in the [Record-shape coverage](#record-shape-coverage)
  table. Config-isolation fixtures are grouped under `config/`.
- **`spec/features/concerns/`** — one file per cross-cutting behavior:
  `filter_spec.rb`, `skip_spec.rb`, `association_if_spec.rb`, `root_key_spec.rb`. Each
  file tests its contract end-to-end across both **Output Modes**.

The axes are orthogonal: a reader asking "how do filters behave?" finds one file; a
reader asking "what's proven for `shallow_generic`?" finds another. Neither file grows
into the other's job. **Compile-time error specs** live at the top level in
`spec/compile_errors_spec.rb` — a separate tier per the [Test tiers](#test-tiers) table,
not under `features/`.

### UL-aligned naming

All test-surface names use the vocabulary from
[../UBIQUITOUS_LANGUAGE.md](../UBIQUITOUS_LANGUAGE.md):

- Directory names: `descriptors/` (per-**Descriptor** specs), not "fixtures" or "corpus."
- Concern file names: `filter_spec.rb`, `skip_spec.rb`, `association_if_spec.rb`,
  `root_key_spec.rb` — each maps 1:1 to a UL term.
- `describe` subjects use the UL concept under test — `describe Filter`, `describe SKIP`,
  `describe "Generated Class for a Descriptor with Associations"`.
- `context` / `it` wording uses UL nouns — `"when the Method Attribute returns SKIP"`,
  `"drops the Association via except: without invoking the if: Callable"`.
- Local and ivar names follow UL — `descriptor`, `record`, `filter`, `context`, `writer`,
  `generated_class`. Never `ser`, `klass`, `object`, or banned aliases.

### JSON/Hash parity — iterated at the describe block

Every concern spec's behavior claim must hold in **both Output Modes**. Parity is
enforced by iterating modes at the top of each `describe` block that needs it:

```ruby
describe "omits the Field when returned from a Method Attribute" do
  %i[json hash].each do |mode|
    context "in #{mode} Output Mode" do
      it "omits the Field"
    end
  end
end
```

- Iteration lives **per describe that needs parity**, not at the file top level.
  File-level wrapping would treat mode as a describe-tree axis (`"JSON mode > Filter > only:"`)
  when it's really an invariant axis.
- Mode-agnostic describe blocks (e.g., `SKIP` singleton identity checks that test the
  constant itself, not serialization) skip the iteration.
- A custom parity matcher (`expect(descriptor).to serialize(record).as(expected)` running
  both modes internally) was considered and deferred: its JSON-parse → Hash equality loses
  byte-order fidelity and masks mode-specific regressions, and the snapshot tier's
  byte-level pinning is a separate line of defense worth preserving here. Revisit if
  parity iteration starts dominating line count.

### Per-concern coverage

Each concern spec enumerates the behavioral contract from the corresponding design doc
and uses the minimum fixture (canonical or inline) needed per test.

#### `filter_spec.rb`

From [filters.md](filters.md):

1. `only:` at a level — only listed **Field** names emit, across **Attribute** /
   **Method Attribute** / **Association**.
2. `except:` at a level — listed names omitted, across all three **Field** kinds.
3. `only:` and `except:` at the same level → `ArgumentError` at `_write_one` /
   `_to_hash` entry.
4. Empty Hash `{}` ≡ `nil` — no filtering.
5. Unknown key at any level — silently ignored (forward-compat).
6. No inheritance — parent-level filter does **not** propagate into child **Association**
   sub-filters.
7. Child-filter key — looked up by the **Association**'s **Source**, not its **name**
   (when they differ).
8. Filter-before-`if:` — an **Association** in `except:` (or omitted from `only:`) is
   dropped **without invoking** its `if:` **Callable** (verified with a spy).
9. `filters: nil` ≡ kwarg omitted.
10. JSON/Hash parity on all of the above.

Fixture strategy: `shallow_generic` for Attributes-only cases; `shallow_specialized` for
**Method Attribute** cases; `nested_composition` for threading-through-**Composition**
and filter-before-`if:` (the fixture's `has_one :author` already carries an `if:`);
inline **Descriptor** for the "**Association** `source` ≠ `name`" case when the corpus
doesn't provide one.

#### `skip_spec.rb`

From [descriptor.md](descriptor.md):

1. Returning `SKIP` from a **Method Attribute** omits the **Field** entirely — no key,
   no value.
2. **Identity, not equality** — a non-SKIP frozen `Object.new` is **not** omitted; the
   **Field** emits.
3. Works across **Method Attribute** arities 0, 1, 2.
4. Adjacent **Fields** (before and after a SKIPped one) emit correctly.
5. Multiple SKIPping **Method Attributes** — all elide.
6. Singleton identity — `SerializersCodeGen::SKIP` is frozen; `SKIP.equal?(SKIP)` stable.
7. JSON/Hash parity on (1)–(5).

Fixture strategy: mostly inline minimal **Descriptors** (1–3 **Method Attributes** each).
`shallow_specialized` already pins SKIP emit at the snapshot tier; the concern spec adds
the focused semantic claims that aren't naturally on a fixture's critical path.

Not tested here: "SKIP doesn't apply to Attributes" (no runtime path — Attributes don't
go through a **Callable**); "SKIP doesn't apply to Association `if:`" (`if:` is
truthy/falsy per descriptor.md, and SKIP-as-`if:` is a contract-misuse case, not a
library contract).

#### `association_if_spec.rb`

From [descriptor.md](descriptor.md) (the `if:` **Callable** contract on **Association**):

1. **Truthy return → Association included**; non-boolean truthy values (`0`, `""`, `[]`,
   `{}`) also count as inclusion (Ruby truthiness).
2. **Falsy return (`nil`, `false`) → key omitted entirely** — not `null`, not `{}`,
   not `[]`.
3. **`has_one` + `if:` falsy → omitted regardless of `null_for_missing_has_one`** — the
   `if:` guard and the nil-Source config are orthogonal omission paths. Pinned at both
   config values to guard against a codegen that accidentally conflates them (e.g., by
   routing the `if:`-falsy path through the same nil-Source branch).
4. **`has_many` + `if:` falsy → omitted** (not `[]`).
5. **`if: nil` (no guard) → Association always emits** (subject only to Source + Filter).
6. **Arity 0 — invoked with no arguments** (`.call`).
7. **Arity 1 — invoked with the Record** (`.call(record)`).
8. **Arity 2 — invoked with `(record, context)`** and threads **Context** unchanged.
9. **Invocation cardinality — once per (Association, Record)** per serialize call. 1 call
   for `serialize_one` with 1 **Record**; N calls for `serialize_many` with N **Records**.
10. JSON/Hash parity on (1)–(9).

Precedence ladder (documented here so the test descriptions stay short):

```
1. Filter.drops?(:assoc) → omit; if: not invoked, Source not called.
2. if: present and returns falsy → omit; Source not called.
3. if: truthy (or absent) → call Source.
   3a. Source returns an object → serialize (the normal case).
   3b. Source returns nil:
        - null_for_missing_has_one: true  → emit "assoc": null
        - null_for_missing_has_one: false → omit the key
```

Fixture strategy: `nested_composition` for `has_one` + `if:` positive and falsy cases
(the fixture's `has_one :author` already carries an `if:`) and the
`null_for_missing_has_one` orthogonality test; inline minimal **Descriptors** for
`has_many` + `if:`, arity variants, and the counting-spy cardinality tests.

**Not tested here (belongs elsewhere):**

- `ArityError` on rejected arities (3+, variadic) → `spec/compile_errors_spec.rb`
  (compile-time tier).
- Filter drops **Association** without invoking `if:` → already covered in
  `filter_spec.rb` (filter-side perspective).
- Purity contract ("must be pure") — documented, not testable as a library contract.
- No ordering guarantee across **Associations** — "no guarantee" pins nothing.

#### `root_key_spec.rb`

From [config.md](config.md), [generated-class.md](generated-class.md), and
[output-modes.md](output-modes.md):

**With `supports_root_key: true`:**

1. `serialize_one` + `root_key: "post"` → wrapped: `{"post":{...}}` in JSON,
   `{"post"=>{...}}` in Hash.
2. `serialize_many` + `root_key: "posts"` → wrapped: `{"posts":[...]}` in JSON,
   `{"posts"=>[...]}` in Hash.
3. `root_key: nil` (explicit) → unwrapped output.
4. `root_key:` kwarg omitted → unwrapped (default is `nil`). Pinned separately from (3)
   to guard against a default drift.
5. **Per-call stability** — same **Generated Class** instance handles successive calls
   with different `root_key` values.
6. **`serialize_many` with empty collection + `root_key:`** → `{"posts":[]}` (wrapped
   empty array, not `{"posts":null}`, not omitted).

**Invalid `root_key` values (with `supports_root_key: true`):**

7. `root_key: ""` (empty String) → `ArgumentError` at call time. Same on
   `serialize_one` and `serialize_many`.
8. `root_key: :post` (Symbol) → `ArgumentError` at call time.
9. `root_key: 42` (non-String, non-nil) → `ArgumentError` at call time.

**With `supports_root_key: false`:**

10. `serialize_one(record, root_key: "post")` → raises Ruby's own `ArgumentError` (the
    kwarg literally does not exist on the generated method). Not library-raised.
11. `serialize_many(records, root_key: "posts")` → same `ArgumentError`.
12. Normal serialization without `root_key:` — unwrapped output.

JSON/Hash parity on (1)–(12) — iterated via `%i[json hash].each`.

Accepted-values contract lives in [generated-class.md](generated-class.md) and
[config.md](config.md): non-empty String or `nil` only.

Fixture strategy: reuse `config_root_key_on` (#7) **DESCRIPTOR** + **CONFIG** for the
`supports_root_key: true` cases; its snapshot `MODES = [:json]` pins only the committed
bytes, but the feature tier can compile the same Descriptor + Config in both modes (they
are mode-orthogonal). For `supports_root_key: false`, `shallow_generic` (#1) with
default **Config** is the smallest.

**Not tested here (no regression surface beyond the direct tests above):**

- Root-key × Filter / `if:` interactions — wrapping is structurally a post-step around
  whatever the serializer produces; no separate regression surface beyond (1)–(2).

#### `spec/compile_errors_spec.rb`

Top-level file per the [Test tiers](#test-tiers) table, not under `features/`. Covers
the full error hierarchy from [errors.md](errors.md).

**Error hierarchy** (3 its): `Error < StandardError`; `DescriptorError` and
`CompileError` direct children; `NameCollisionError`, `UnknownSourceError`, `ArityError`
under `CompileError`.

**`DescriptorError` — structural, at `Data.new`** (grouped by Data type):

- **Descriptor**: name nil / empty String; models contains non-Class; attributes /
  method_attributes / associations contain wrong element types.
- **Attribute**: name or source not a Symbol.
- **MethodAttribute**: body doesn't respond to `.call`.
- **Association**: kind not in `{:has_one, :has_many}`; descriptor isn't a **Descriptor**;
  `if:` present but not a **Callable**.

**`CompileError` subclasses — semantic, at `Compile`:**

- **`NameCollisionError`** — two **Fields** sharing a name, covering all four Field-kind
  pairings; collision inside a nested **Descriptor** (message names the nested Descriptor);
  same name across different levels does **not** raise.
- **`UnknownSourceError`** — `Models: [AR]` with source neither column nor instance
  method; `Models: [Class1, Class2]` mixed with non-uniform backing; `Models: nil` does
  **not** raise at Compile (defers to runtime `NoMethodError`).
- **`ArityError`** — MethodAttribute body or Association `if:` with arity 3 / -1 / -2
  raises; arity 0 / 1 / 2 compiles successfully (positive cases pin the allowed set,
  guarding against false-positive validation).

**Message convention** — a dedicated `describe` block pins the format from errors.md
("Message convention") on one representative error per subclass: message includes
**Descriptor** `name`, **Field** name + kind, the specific rule violated, and the
observed value. Example to match: `"PostDescriptor#likes_count: MethodAttribute#body has
arity 3; must be 0, 1, or 2."`

**Mode independence** — 6 its: `[NameCollisionError, UnknownSourceError, ArityError]` ×
`%i[json hash]`. Pins that semantic validation is pre-Generator and mode-independent.
`DescriptorError` doesn't need mode iteration — it raises at `Data.new`, before
`Compile` is called.

~35 `it` blocks total, proportional to the error surface. One consolidated file per the
tier table — the `describe` tree mirrors the hierarchy, so the file stays scannable.

**Fixture strategy:** mostly inline invalid **Descriptors** (corpus fixtures are the
valid cases). `UnknownSourceError` tests use AR classes from `spec/support/models.rb`
(loaded globally via `spec_helper`) with a deliberately-missing source.

**Not tested here (out of contract):**

- Runtime errors (missing method on **Record**, misbehaving **Callable** body) — per
  errors.md, not wrapped; surface as Ruby's own exceptions.
- `ArgumentError` on unknown kwargs (`root_key:` when `supports_root_key: false`) —
  Ruby-raised, covered in `root_key_spec.rb`.
- Synthetic-path backtrace format drift — pinned at the snapshot tier if anywhere.

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

- **Benchmark harness.** See [open-questions.md](open-questions.md) — benchmark-ips +
  memory_profiler, target comparisons, regression guard.

The feature-test coverage matrix for cross-cutting concerns is fully resolved — see
[Feature-test organization](#feature-test-organization) above.
