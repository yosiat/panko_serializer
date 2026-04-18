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

Only methods that require **per-serializer unrolling**, **literal method names**, or **skipping absent concerns** are generated. Everything else lives as pre-written Ruby on `GeneratedBase`.

| Method | Generated? | Why |
|--------|-----------|-----|
| `_write_indexed_cached` (+ hash) | Yes | HOT PATH — unrolled per-attribute with literal indices |
| `_write_plain` (+ hash) | Yes | Literal method calls: `object.name` |
| `_write_hash` (+ hash) | Yes | Literal key lookups: `object["name"]` |
| `_write_one` (+ hash) | Yes | Top-level dispatch. Computes `is_ar` once, inlines method fields / has_one / has_many blocks when present, elides them otherwise. Owns `push_object(key) / pop` on the JSON path. |
| `_write_indexed_first_pass` (+ hash) | No | Cold path (runs once), loop over attrs array |
| `_write_ar_fallback` (+ hash) | No | Cold path (dirty/non-indexed records), loop |
| `_serialize_many` | No | Generic batch loop — just calls `_write_one` per element |

Method fields, has_one, and has_many are no longer separate methods. They are **inlined** into `_write_one` / `_write_one_hash` by the Dispatch compiler module — absent concerns generate no code at all.

## Compiler Structure

`compiler.rb` is the entry point. It delegates to focused modules in `compiler/`:

| Module | Generates |
|--------|-----------|
| `active_record_methods.rb` | `_write_indexed_cached` (+ hash) |
| `object_methods.rb`        | `_write_plain`, `_write_hash` (+ hash) |
| `dispatch.rb`              | `_write_one` (+ hash) — inlines method fields / has_one / has_many |

## Emitter Structure

`emitter.rb` is a simple line collector (`<<` appends a line, `to_source` joins them). It delegates to focused modules in `emitter/`:

| Module | Emit methods |
|--------|-------------|
| `active_record_attributes.rb` | `emit_cached_attr` (+ hash) |
| `object_attributes.rb`        | `emit_plain_attr`, `emit_hash_attr` (+ hash) |
| `method_fields.rb`            | `emit_method_field` (+ hash) — called from Dispatch |
| `associations.rb`             | `emit_has_one`, `emit_has_many` (+ hash) — called from Dispatch |

Association emitters assume the following locals are in scope (set up by Dispatch at the top of `_write_one`):

- `is_ar` — boolean, `object.is_a?(ActiveRecord::Base)` computed once
- `ho_mask` / `hm_mask` / `mf_mask` — inclusion mask for this level
- `ho_masks` / `hm_masks` — per-slot nested override masks (may be the `NIL_SLOTS` sentinel)

## Filter Masks

`FilterMask::EMPTY` and every `FilterMask` built by `compute_filter_mask` populate **all** slots — never raw `nil`. Sentinel objects fill in for "include everything":

- `INCLUDE_ALL` — `#[]` returns `true` for any index. Used for `attrs`, `method_fields`, `has_one`, `has_many` when unfiltered.
- `NIL_SLOTS` — `#[]` returns `nil` for any index. Used for `has_one_masks` / `has_many_masks` when no caller overrides exist; the generated code then falls back to `@_ho_static_masks[i]` / `@_hm_static_masks[i]` (which are always non-nil `FilterMask`s — `FilterMask::EMPTY` when the association has no static filter).

This means generated code never needs `.nil?` / `&.` on masks. The pattern is `if ho_mask[i]` and `nested = ho_masks[i] || @_ho_static_masks[i]`.

## Two-Phase Initialization

Column indices from the DB result set are only known at runtime, so code-gen is two-phase:

1. **Structural (compile time)** — attribute names, JSON keys, association graph, method field names. All baked into the generated source.
2. **Runtime (first call)** — `_write_indexed_first_pass` (pre-written loop) resolves types, populates `cached_writer` on each Attribute, then `build_caches!` fills the parallel arrays (`col`, `key`, `wtr`, `dir`). All subsequent calls hit `_write_indexed_cached` (fully unrolled, no loop).

## Rules for Generated Code

- **No `public_send`.** Names are known at compile time — emit `object.posts`, `ser.method_name`.
- **No constant assignment.** Use full paths: `Panko::Engine::SKIP`, not `SKIP = ...`.
- **No loops over compile-time-known data.** One explicit line per attribute/field/association.
- **No `.nil?` / `&.` on filter masks.** Defaults live in sentinels (`INCLUDE_ALL`, `NIL_SLOTS`, `FilterMask::EMPTY` static-mask slots).
- **Emitters take literal values.** Pass `attr.name`, `attr.name_for_serialization`, `attr.name_sym` as arguments — don't emit `attrs[i].name` lookups in hot paths.
- **Only generate what requires it.** If a concern is absent from a serializer, emit nothing for it. If a method can be a pre-written loop on `GeneratedBase`, it should be.

## Debugging / Inspecting Generated Code

Use `dump_generated_source` on any serializer class to see the generated methods:

```ruby
MySerializer.dump_generated_source              # => String
MySerializer.dump_generated_source(file: "/tmp/my_serializer.rb")  # writes to file
```

Labels include the serializer name and field info for easy identification.

## Adding a New Feature

1. Decide if the feature needs code generation (literal method names, hot-path unrolling, skipping absent concerns) or can be a pre-written method on `GeneratedBase`.
2. If generated: add emitter method(s) in `emitter/`, compiler method(s) in `compiler/`, wire `define_on` in `compiler.rb`.
3. If pre-written: add the method to `GeneratedBase`.
4. Run `bundle exec appraisal rake` and `bundle exec rubocop`.
