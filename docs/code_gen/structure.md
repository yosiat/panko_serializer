# Project structure

Public API surface, directory layout, and the layered architecture for the engine's internals.

## Gem identity

- **Require path**: `require "panko/code_gen"`.
- **Top-level module**: `Panko::CodeGen`.
- **Published?** Not separately. The engine ships inside the `panko` gem — pure
  Ruby, MIT-licensed, merged into the `panko_serializer` tree with its history.
  There is no standalone gem to install and no native extension to compile.

## Public API surface

These are the only symbols Panko — the sole caller — depends on. Everything else under
`lib/panko/code_gen/` is internal and may change without notice.

| Public symbol                                                                                          | Purpose                                                    |
| ------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| `Panko::CodeGen.compile(descriptor, output:, config:)`                                                 | **Compile** entry — returns a **Generated Class**.         |
| `Panko::CodeGen.dump(descriptor, output:, config:, path:)`                                             | **Dump** entry — writes a runnable `.rb` file.             |
| `Panko::CodeGen::Descriptor`, `Attribute`, `MethodAttribute`, `Association`                            | **Descriptor** value types (all `Data.define`).            |
| `Panko::CodeGen::Config`                                                                               | Compile-time settings (`Data.define`).                     |
| `Panko::CodeGen::SKIP`                                                                                 | Frozen singleton returned by **Method Attributes** to omit a **Field**. |
| `Panko::CodeGen::Error` + descendants (`DescriptorError`, `CompileError`, `NameCollisionError`, …)     | Error hierarchy — see [errors.md](errors.md).              |

Both module-level facades are thin wrappers:

```ruby
module Panko::CodeGen
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
Panko::CodeGen.compile(...)                     # facade — thin wrapper
  └─ Compiler#compile                           # orchestration: drive generation + eval
      ├─ Generator#emit                         # walks Descriptor, decides what to emit
      │   └─ CodeBuilder                        # accumulates strings, tracks indent — pure helper
      └─ Module.new + module_eval               # materialization: source → runnable class

Panko::CodeGen.dump(...)                        # facade — thin wrapper
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

Each file handles a single concept and stays small. Domains grouped into folders;
filenames mirror the concepts in the other docs. The engine core sits alongside the
Panko **runtime seam** that replaced the deleted C extension.

```
lib/
  panko/
    code_gen.rb                                # facade: .compile / .dump; requires the subtree

    code_gen/
      version.rb                               # VERSION + GENERATOR_NAME (dumped-file banner text)

      # === Domain types ===
      descriptor.rb                            # Descriptor + Attribute + MethodAttribute +
                                               # Association + SKIP + structural validation
      config.rb                                # Config Data.define + enum coercion
      errors.rb                                # error hierarchy (see errors.md)
      datetime_format.rb                       # raw DB datetime String → ISO-8601 String splicer

      # === Semantic validation (one rule per file, one orchestrator) ===
      validators/
        validator.rb                           # runs all rules, raises on first violation
        name_uniqueness.rb                     # two Fields sharing a name
        source_resolution.rb                   # specialized-path Attribute source must resolve
        callable_arity.rb                      # Callable arity ∈ {0, 1, 2, 3}
        symbol_body_dispatch.rb                # Symbol body ⇒ Descriptor#parent_class non-nil

      # === Filter ===
      filter.rb                                # Filter.wrap(hash) factory + interface
      filters/
        none.rb                                # no-filter singleton (Null Object)
        indexed.rb                             # Indexed filter — bit-mask (≤63 Fields) or
                                               # Boolean Array (>63 Fields); see filters.md and
                                               # research/filter_experiments_results.md

      # === Compilation orchestration ===
      compiler.rb                              # Compiler#compile: drive Generator + module_eval
      compile_cache.rb                         # identity-keyed Descriptor → Generated Class cache
                                               # (handles Recursive Descriptors)

      # === Code generation ===
      code_builder.rb                          # pure indented-line accumulator
      generator.rb                             # Generator entry — dispatches on Output Mode
      generators/
        generated_names.rb                     # the emitted-symbol vocabulary: ivar tokens,
                                               # write-method names, FIELD_INDEX, pool key,
                                               # filter-key rule — one home, emitters consume it
        json_mode.rb                           # JSON-mode source emission (top-level)
        hash_mode.rb                           # Hash-mode source emission (top-level)
        banner.rb                              # header-comment banner (see dumping.md)
        descriptor_walk.rb                     # post-order unique-Descriptor tree walk
        cycle_membership.rb                    # identity-keyed mutual-recursion cycle set
        field_index.rb                         # per-class Symbol → Integer FIELD_INDEX map
                                               # (filter-key keyed: name for value Fields, Source for Associations; feeds filters/indexed.rb)
        release.rb                             # _release generator — checkin-side ivar cleanup
        fanout.rb                              # multi-file dump fan-out (one file per Descriptor)
        field_emitters/
          attribute.rb                         # emit one Attribute
          method_attribute.rb                  # emit one Method Attribute (Callable / Symbol body)
          association.rb                        # emit one Association (nested call threading)
        record_access/
          generic.rb                           # generic path — one is_a?(Hash) branch, both
                                               # emit shapes inlined; splits to per-shape helpers
                                               # above 64 Fields (FUSED_DISPATCH_MAX_FIELDS)
          specialized.rb                       # specialized path — _read_attribute / method dispatch

      # === Dump ===
      dump.rb                                  # Dump#dump: drive Generator + File.write

      # === ActiveRecord helpers ===
      active_record/
        access_classifier.rb                   # 3-step rule: column-backed / method / raise
        define_attribute_methods.rb            # defensive idempotent AR method-table warmup

      # === Generated-Class runtime support ===
      writers_pool.rb                          # fiber-local LIFO of Oj::StringWriter instances,
                                               # frozen into each JSON Generated Class

      # === Panko runtime seam (replaces the deleted C extension) ===
      runtime.rb                               # shared seam: only/except/filters_for → Filter
      descriptor_builder.rb                    # Panko::Serializer DSL → immutable Descriptor
      serializer_cache.rb                      # per-class base + auto-specialization variant pools
      filter_adapter.rb                        # Panko filter shape → engine Filter shape
      instance_pool.rb                         # fiber-local LIFO of Generated Class instances
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
not weaken test coverage. CI still runs the Ruby × Rails matrix (Ruby 3.4 / 4.0 × Rails
7.2 / 8.0 / 8.1, minus the incompatible Ruby 4.0 × Rails 7.2 cell) to prove the
single-path code works on every supported combination.

## Mapping docs to files

A reader arriving from a doc should know exactly where the implementation lives. Paths
are relative to `lib/panko/code_gen/`.

| Doc                                          | Primary files                                                              |
| -------------------------------------------- | -------------------------------------------------------------------------- |
| [descriptor.md](descriptor.md)               | `descriptor.rb`, `validators/*`                                            |
| [config.md](config.md)                       | `config.rb`                                                                |
| [errors.md](errors.md)                       | `errors.rb`                                                                |
| [filters.md](filters.md)                     | `filter.rb`, `filters/*`, `generators/field_index.rb`                      |
| [compilation.md](compilation.md)             | `compiler.rb`, `compile_cache.rb`, `generator.rb`, `generators/*`          |
| [code-generation.md](code-generation.md)     | `code_builder.rb`, `generator.rb`, `generators/*`                          |
| [output-modes.md](output-modes.md)           | `generators/json_mode.rb`, `generators/hash_mode.rb`                       |
| [generated-class.md](generated-class.md)     | shape emitted by `generators/*`; runtime support in `writers_pool.rb`, `instance_pool.rb` |
| [dumping.md](dumping.md)                      | `dump.rb`, `generators/fanout.rb`, `generators/banner.rb`                  |
| [merging-into-panko.md](merging-into-panko.md) | `runtime.rb`, `descriptor_builder.rb`, `serializer_cache.rb`, `filter_adapter.rb`, `instance_pool.rb` |
| [auto-specialization.md](auto-specialization.md) | `serializer_cache.rb`                                                  |

## Testing shape (preview)

The small-file split exists so every file has an obvious unit-test target:

- `code_builder_spec.rb` — pure string/indent behavior; no domain types involved.
- `generators/snapshot_spec.rb` — "given this fixture **Descriptor**, the emitted source is
  exactly X" — snapshot-style.
- `validators/name_uniqueness_spec.rb` — feed Descriptors with duplicate Field names,
  assert `NameCollisionError` raised.
- `features/*` — end-to-end: compile a fixture **Descriptor**, serialize, assert output.

Full testing strategy — tiers, snapshot harness, feature-test fixtures — is in
[testing.md](testing.md).
</content>
</invoke>
