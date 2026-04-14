# Code Generation — Compiler & Emitter

## How It Works

The `Compiler` takes a canonical (unfiltered) `SerializationDescriptor` and produces an anonymous `Class < GeneratedBase` with all serialization methods baked in as class methods via `module_eval`.

```
Compiler.new(descriptor).compile
  -> builds Emitter instances to generate source strings
  -> module_eval's each method onto the new class
  -> returns the class (cached on the descriptor)
```

## What Is Generated vs Pre-Written

Only methods that require **per-serializer unrolling** or **literal method names** are generated. Everything else lives as pre-written Ruby on `GeneratedBase`.

| Method | Generated? | Why |
|--------|-----------|-----|
| `_write_indexed_cached` (+ hash) | Yes | HOT PATH — unrolled per-attribute with literal indices |
| `_write_plain` (+ hash) | Yes | Literal method calls: `object.name` |
| `_write_method_fields` (+ hash) | Yes | Literal method calls: `ser.method_name` |
| `_write_has_one` (+ hash) | Yes | Literal method calls: `object.assoc_name` |
| `_write_has_many` (+ hash) | Yes | Literal method calls: `object.assoc_name` |
| `_write_indexed_first_pass` (+ hash) | No | Cold path (runs once), loop over attrs array |
| `_write_ar_fallback` (+ hash) | No | Cold path (dirty/non-indexed records), loop |
| `_write_hash` (+ hash) | No | Hash objects use `object[key]`, no method calls |
| `_write_one`, `_write_one_hash` | No | Generic dispatch (AR/Hash/PORO) |
| `_serialize_many` | No | Generic batch dispatch |
| `_write_method_fields` (stub) | No | No-op, overridden when serializer has method fields |
| `_write_has_one/many` (stubs) | No | No-op, overridden when serializer has associations |

## Compiler Structure

`compiler.rb` is the entry point. It delegates to focused modules in `compiler/`:

| Module | Generates |
|--------|-----------|
| `active_record_methods.rb` | `_write_indexed_cached` (+ hash variant) |
| `object_methods.rb` | `_write_plain` for PORO objects (+ hash variant) |
| `method_fields.rb` | `_write_method_fields` (+ hash variant) |
| `associations.rb` | `_write_has_one`, `_write_has_many` (+ hash variants) |

## Emitter Structure

`emitter.rb` is a simple line collector (`<<` appends a line, `to_source` joins them). It delegates to focused modules in `emitter/`:

| Module | Emit methods |
|--------|-------------|
| `active_record_attributes.rb` | `emit_cached_attr` (+ hash variant) |
| `object_attributes.rb` | `emit_plain_attr` (+ hash variant) |
| `method_fields.rb` | `emit_method_field` (+ hash variant) |
| `associations.rb` | `emit_has_one`, `emit_has_many` (+ hash variants) |

## Two-Phase Initialization

Column indices from the DB result set are only known at runtime, so code-gen is two-phase:

1. **Structural (compile time)** — attribute names, JSON keys, association graph, method field names. All baked into the generated source.
2. **Runtime (first call)** — `_write_indexed_first_pass` (pre-written loop) resolves types, populates `cached_writer` on each Attribute, then `build_caches!` fills the parallel arrays (`col`, `key`, `wtr`, `dir`). All subsequent calls hit `_write_indexed_cached` (fully unrolled, no loop).

## Rules for Generated Code

- **No `public_send`.** Names are known at compile time — emit `object.posts`, `ser.method_name`.
- **No constant assignment.** Use full paths: `Panko::Engine::SKIP`, not `SKIP = ...`.
- **No loops over compile-time-known data.** One explicit line per attribute/field/association.
- **Emitters take literal values.** Pass `attr.name`, `attr.name_for_serialization`, `attr.name_sym` as arguments — don't emit `attrs[i].name` lookups in hot paths.
- **Only generate what requires it.** If a method can be a pre-written loop on `GeneratedBase`, it should be.

## Debugging / Inspecting Generated Code

Use `dump_generated_source` on any serializer class to see the generated methods:

```ruby
MySerializer.dump_generated_source              # => String
MySerializer.dump_generated_source(file: "/tmp/my_serializer.rb")  # writes to file
```

Labels include the serializer name and field info for easy identification.

## Adding a New Feature

1. Decide if the feature needs code generation (literal method names, hot-path unrolling) or can be a pre-written method on `GeneratedBase`.
2. If generated: add emitter method(s) in `emitter/`, compiler method(s) in `compiler/`, wire `define_on` in `compiler.rb`.
3. If pre-written: add the method to `GeneratedBase` (with no-op stub if optional).
4. Run `bundle exec appraisal rake` and `bundle exec rubocop`.
