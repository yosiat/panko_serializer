# Code Generation — Compiler & Emitter

## How It Works

The `Compiler` takes a canonical (unfiltered) `SerializationDescriptor` and produces an anonymous `Class < GeneratedBase` with all serialization methods baked in as class methods via `module_eval`.

```
Compiler.new(descriptor).compile
  -> builds Emitter instances to generate source strings
  -> module_eval's each method onto the new class
  -> returns the class (cached on the descriptor)
```

## Compiler Structure

`compiler.rb` is the entry point. It delegates to focused modules in `compiler/`:

| Module | Generates |
|--------|-----------|
| `active_record_methods.rb` | `_write_indexed_cached`, `_write_indexed_first_pass`, `_write_ar_fallback` (+ filtered + hash variants) |
| `object_methods.rb` | `_write_hash`, `_write_plain` (for Hash/PORO objects) (+ filtered + hash variants) |
| `method_fields.rb` | `_write_method_fields` (+ filtered + hash variants) |
| `associations.rb` | `_write_has_one`, `_write_has_many` (+ filtered + hash variants) |
| `dispatch.rb` | `_write_one` (top-level object-type dispatch), `_write_one_hash`, `_serialize_many` |

Each method is generated in two variants:
- **JSON path** — writes to `Oj::StringWriter` via `writer.push_value(v, key)`
- **Hash path** — writes to a Ruby Hash via `result[key] = v`

And each variant has filtered/unfiltered versions (filtered adds `if mask[i]` guards).

## Emitter Structure

`emitter.rb` is a simple line collector (`<<` appends a line, `to_source` joins them). It delegates to focused modules in `emitter/`:

| Module | Emit methods |
|--------|-------------|
| `active_record_attributes.rb` | `emit_cached_attr`, `emit_first_pass_attr`, `emit_indexed_with_hash_attr`, `emit_non_indexed_attr` (+ filtered + hash variants) |
| `object_attributes.rb` | `emit_hash_attr`, `emit_plain_attr` (+ filtered + hash variants) |
| `method_fields.rb` | `emit_method_field` (+ filtered + hash variants) |
| `associations.rb` | `emit_has_one`, `emit_has_many` (+ filtered + hash variants) |

## Two-Phase Initialization

Column indices from the DB result set are only known at runtime, so code-gen is two-phase:

1. **Structural (compile time)** — attribute names, JSON keys, association graph, method field names. All baked into the generated source.
2. **Runtime (first call)** — `_write_indexed_first_pass` resolves types, populates `cached_writer` on each Attribute, then `build_caches!` fills the parallel arrays (`col`, `key`, `wtr`, `dir`). All subsequent calls hit `_write_indexed_cached` (fully unrolled, no loop).

## Rules for Generated Code

- **No `public_send`.** Names are known at compile time — emit `object.posts`, `ser.method_name`.
- **No constant assignment.** Use full paths: `Panko::Engine::SKIP`, not `SKIP = ...`.
- **No loops over compile-time-known data.** One explicit line per attribute/field/association.
- **Emitters take literal values.** Pass `attr.name`, `attr.name_for_serialization`, `attr.name_sym` as arguments — don't emit `attrs[i].name` lookups in hot paths.

## Adding a New Feature

1. Add the emitter method(s) in the appropriate `emitter/` module — both JSON and Hash variants.
2. Add the compiler method(s) in the appropriate `compiler/` module that call the emitters.
3. Wire the new `define_on` calls in `compiler.rb`'s `compile` method.
4. If the feature needs runtime helpers, add them to `generated_base.rb`.
5. Run `bundle exec appraisal rake` and `bundle exec rubocop`.
