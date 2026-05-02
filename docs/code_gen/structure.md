# Project structure

Public API surface, directory layout, and the layered architecture for the gem's internals.

## Gem identity

- **Gem name**: `serializers_code_gen` (snake_case — `require "serializers_code_gen"`).
- **Top-level module**: `SerializersCodeGen`.
- **Published?** No — internal to the Panko ecosystem; distributed as a path or git
  dependency for now.

## Public API surface

These are the only symbols callers (Panko) should depend on. Everything else in `lib/` is
internal and may change without notice.

| Public symbol                                                                                          | Purpose                                                    |
| ------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| `SerializersCodeGen.compile(descriptor, output:, config:)`                                             | **Compile** entry — returns a **Generated Class**.         |
| `SerializersCodeGen.dump(descriptor, output:, config:, path:)`                                         | **Dump** entry — writes a runnable `.rb` file.             |
| `SerializersCodeGen::Descriptor`, `Attribute`, `MethodAttribute`, `Association`                        | **Descriptor** value types (all `Data.define`).            |
| `SerializersCodeGen::Config`                                                                           | Compile-time settings (`Data.define`).                     |
| `SerializersCodeGen::SKIP`                                                                             | Frozen singleton returned by **Method Attributes** to omit a **Field**. |
| `SerializersCodeGen::Error` + descendants (`DescriptorError`, `CompileError`, `NameCollisionError`, …) | Error hierarchy — see [errors.md](errors.md).              |

Both module-level facades are thin wrappers:

```ruby
module SerializersCodeGen
  def self.compile(descriptor, output:, config: Config.new)
    Compiler.new(descriptor, output:, config:).compile
  end

  def self.dump(descriptor, output:, config: Config.new, path:)
    Dump.new(descriptor, output:, config:, path:).dump
  end
end
```

## Layered architecture

Three layers. Each layer knows only about the layer immediately below it. `Compiler` and
`Dump` share the lower two layers — they differ only in how they **materialize** the
emitted source.

```
SerializersCodeGen.compile(...)                 # facade — thin wrapper
  └─ Compiler#compile                           # orchestration: drive generation + eval
      ├─ Generator#emit                         # walks Descriptor, decides what to emit
      │   └─ CodeBuilder                        # accumulates strings, tracks indent — pure helper
      └─ Module.new + module_eval               # materialization: source → runnable class

SerializersCodeGen.dump(...)                    # facade — thin wrapper
  └─ Dump#dump                                  # orchestration: drive generation + write file
      ├─ Generator#emit                         # same generator, same output bytes
      │   └─ CodeBuilder
      └─ File.write                             # materialization: source → .rb file on disk
```

**Contract**: for identical inputs, `Compiler` and `Dump` produce **byte-identical**
source. The only difference is what they do with it.

### Responsibilities

| Layer           | Knows about                                            | Does not know about                              |
| --------------- | ------------------------------------------------------ | ------------------------------------------------ |
| **Compiler**    | **Descriptor**, **Output Mode**, **Config**, eval mechanics, recursion cache | How lines are accumulated; field-emit details    |
| **Dump**        | Same as Compiler, plus file-system paths               | Same as Compiler                                 |
| **Generator**   | **Descriptor** tree walking, per-**Field** emit rules, **Output Mode** branching | Eval, file I/O, how strings are stored           |
| **CodeBuilder** | Strings and indent levels                              | **Descriptors**, **Output Modes**, Ruby semantics |

That boundary is what makes `CodeBuilder` trivially unit-testable (pure helper) and
`Generator` testable against fixture **Descriptors** with no class-materialization
machinery in play.

## Directory layout

Each file handles a single concept and stays under ~200 lines. Domains grouped into
folders. Filenames mirror the concepts in the other docs.

```
lib/
  serializers_code_gen.rb                      # facade: .compile, .dump; requires subtree

  serializers_code_gen/
    version.rb

    # === Domain types ===
    descriptor.rb                              # Descriptor + Attribute + MethodAttribute +
                                               # Association + SKIP (small Data.defines in one file)
    config.rb                                  # Config Data.define
    errors.rb                                  # error hierarchy (see errors.md)

    # === Semantic validation (one rule per file, one orchestrator) ===
    validators/
      validator.rb                             # runs all rules, raises on first violation
      name_uniqueness.rb                       # two Fields sharing a name
      source_resolution.rb                     # specialized-path Attribute source must resolve
      callable_arity.rb                        # Callable arity ∈ {0, 1, 2}

    # === Filter ===
    filter.rb                                  # Filter.wrap(hash) factory + interface
    filters/
      none.rb                                  # no-filter singleton (Null Object)
      indexed.rb                               # winning cell from S13's verdict —
                                               # bit-mask (≤63 Fields) or Boolean Array
                                               # (>63 Fields); see filters.md and
                                               # research/filter_experiments_results.md

    # === Compilation orchestration ===
    compiler.rb                                # Compiler#compile: drive Generator + eval
    compile_cache.rb                           # identity-keyed Descriptor → Generated Class cache
                                               # (handles Recursive Descriptors)

    # === Code generation ===
    code_builder.rb                            # pure string accumulator + indent tracker
    generator.rb                               # Generator entry — dispatches to mode
    generators/
      json_mode.rb                             # JSON-mode source emission (top-level)
      hash_mode.rb                             # Hash-mode source emission (top-level)
      field_emitters/
        attribute.rb                           # emit one Attribute
        method_attribute.rb                    # emit one Method Attribute
        association.rb                         # emit one Association (nested call threading)
      record_access/
        generic.rb                             # _write_one_hash / _write_one_object generator
        specialized.rb                         # _read_attribute / method-dispatch generator

    # === Dump ===
    dump.rb                                    # Dump#dump: drive Generator + File.write

    # === ActiveRecord helpers ===
    active_record/
      access_classifier.rb                     # 3-step rule: column-backed / method / raise
      define_attribute_methods.rb              # defensive call wrapper
```

### Why no per-Rails-version adapter folder

An earlier sketch had `ar_adapter/rails_7_2.rb`, `rails_8_0.rb`, etc. That was
speculative. The research notes in
[`research/define_attribute_methods_safety.md`](research/define_attribute_methods_safety.md)
show `define_attribute_methods` is byte-identical across Rails 7.2 / 8.0 / 8.1, and
[`research/ar_access_results.md`](research/ar_access_results.md) confirms `_read_attribute`
is stable across the supported versions. There is no version-specific surface today, so
there are no version-specific files.

If a future Rails version breaks one of these contracts, the fix is a feature-detect
switch inside the affected `active_record/*.rb` helper — not a new file tree.

The absence of a per-version adapter folder is a **code-structure** decision — it does
not weaken test coverage. CI still runs a matrix (Ruby 3.4.x × 4.0.x × Rails 7.2 / 8.0 /
8.1, minus the incompatible Ruby 4.0 × Rails 7.2 cell) to prove the single-path code
works on every supported combination. See [ci.md](ci.md).

## Mapping docs to files

A reader arriving from a doc should know exactly where the implementation lives.

| Doc                                      | Primary files                                                        |
| ---------------------------------------- | -------------------------------------------------------------------- |
| [descriptor.md](descriptor.md)           | `descriptor.rb`, `validators/*`                                      |
| [config.md](config.md)                   | `config.rb`                                                          |
| [errors.md](errors.md)                   | `errors.rb`                                                          |
| [filters.md](filters.md)                 | `filter.rb`, `filters/*`                                             |
| [compilation.md](compilation.md)         | `compiler.rb`, `compile_cache.rb`, `generator.rb`, `generators/*`    |
| [code-generation.md](code-generation.md) | `code_builder.rb`, `generator.rb`, `generators/*`                    |
| [output-modes.md](output-modes.md)       | `generators/json_mode.rb`, `generators/hash_mode.rb`                 |
| [generated-class.md](generated-class.md) | (runtime-only — no direct implementation file; shape is emitted by the generator) |
| [dumping.md](dumping.md)                 | `dump.rb`                                                            |

## Testing shape (preview)

The small-file split exists so every file has an obvious unit-test target:

- `code_builder_spec.rb` — pure string/indent behavior; no domain types involved.
- `generators/field_emitters/attribute_spec.rb` — "given this fixture **Attribute**, the
  emitted lines are exactly X" — snapshot-style.
- `validators/name_uniqueness_spec.rb` — feed Descriptors with duplicate Field names,
  assert `NameCollisionError` raised.
- `compiler_spec.rb` — end-to-end: compile a fixture **Descriptor**, serialize, assert
  output.

Full testing strategy — tiers, snapshot harness, feature-test fixtures — is in
[testing.md](testing.md).
