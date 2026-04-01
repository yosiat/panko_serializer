# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Non-Negotiable Before Every Commit

Before committing any code change, **both** of these must pass with zero errors:

1. `bundle exec appraisal rake` — all tests across all Rails versions
2. `bundle exec rubocop` — zero offenses (use `-a` / `-A` to auto-correct)

These are equally critical. A commit with failing tests or rubocop offenses is not acceptable.

## Commands

```bash
# Run tests
bundle exec rake

# Run a single spec file
bundle exec rspec spec/panko/serializer_spec.rb

# Lint Ruby
bundle exec rake rubocop

# Auto-correct Ruby lint issues
bundle exec rubocop -a

# Run all benchmarks
bundle exec rake benchmarks:all

# Run a specific benchmark
bundle exec rake benchmarks:run[panko_json]

# Run type_casts benchmarks (all or specific provider)
bundle exec rake benchmarks:run[type_casts]
bundle exec rake benchmarks:run[type_casts:postgresql]

# Env vars: BENCH=pattern SIZE=N PROFILE=cpu|memory IPS_TIME=N IPS_WARMUP=N
BENCH=HasOne ruby benchmarks/panko_json.rb
SIZE=2300 ruby benchmarks/panko_json.rb
PROFILE=cpu ruby benchmarks/panko_json.rb

# Test all versions of Rails (import for sanity checks)
bundle exec appraisal rake

# Test against a specific Rails version (uses Appraisal)
bundle exec appraisal 8.0.0 rake

# Regenerate gemfiles after editing Appraisals
bundle exec appraisal install
```

## Documentation Conventions

All public and internal methods, classes, and `attr_reader`/`attr_accessor` declarations must be documented with RDoc. Use `@param`, `@return`, and type annotations. Be specific about types.

**Methods:**
```ruby
# Serializes +object+ into +writer+ under the given +key+.
#
# @param object [ActiveRecord::Base] the record to serialize
# @param writer [Oj::StringWriter] the output writer
# @param key [String, nil] JSON key under which the object is nested; nil for root
# @return [void]
def serialize_one(object:, writer:, key: nil)
```

**`attr_reader` / `attr_accessor` on classes with multiple ivars** — add an inline comment per reader explaining *what* it holds and *why* it exists:
```ruby
# The column name → array index map for the current IndexedRow.
# Why: allows O(1) lookup of a field's position in the raw row array,
# avoiding AR's attribute hash lookup on every serialized field.
# @return [Hash{String => Integer}, nil]
attr_reader :column_indexes
```

Private methods do not need RDoc unless their purpose is non-obvious.

## Architecture

Panko is a high-performance JSON serializer for ActiveRecord and Ruby objects. It pre-computes serialization metadata at class load time and uses `Oj::StringWriter` for incremental JSON generation.

### Core Serialization Flow

```
Serializer.new(options)
  → SerializationContext.create(options)
  → SerializationDescriptor.build(serializer_class)   # cached metadata
  → Panko::Filters.apply(descriptor, options)          # :only/:except filtering
  → Panko::Engine::Serializer
  → Engine::AttributesWriter (AR/Hash/Plain depending on object type)
  → Oj::StringWriter (JSON output)
```

### Key Components

**`lib/panko/serializer.rb`** — Base class with DSL (`attributes`, `has_one`, `has_many`, `aliases`). Stores class-level metadata. Single-use by design (`@used` flag).

**`lib/panko/serialization_descriptor.rb`** — Plain data container: pre-computes and caches attribute/association metadata per serializer class. Delegates all `:only`/`:except` filtering to `Panko::Filters`. Do not add AR-specific logic here.

**`lib/panko/filters.rb`** — Stateless filter engine (`Panko::Filters.apply`). Resolves `:only`/`:except` options against a descriptor's attributes, method_fields, and associations. Uses a frozen `INSTANCE` singleton to avoid repeated allocation.

**`lib/panko/attribute.rb`** — Represents a single serializable field. Holds the field name, optional alias, resolved type, and cached writer. AR-specific concerns (type resolution, alias lookup) are handled externally by `ActiveRecord::Writer` and `RecordState`. `invalidate!` clears the cached type and writer only — it takes no arguments.

**`lib/panko/engine/serializer.rb`** — The hot-path serialization engine. Contains multiple fast paths:
- Ultra-fast: attributes only, no methods/associations
- Fast: attributes + has_one
- Full: attributes + methods + associations

`_serialize_one(object, writer, key = nil)` is the shared internal helper — public by convention because association sub-serializers call it directly. `_serialize_many` fast paths inline their work and do not call `_serialize_one`.

Optimized to use positional args, inline method calls, and bypass Rails association proxies (`association().target` instead of `public_send`).

**`lib/panko/engine/attributes_writer/`** — Type-specific writers selected at runtime:
- `active_record/writer.rb` — Thin orchestrator. Calls `RecordState#setup`, handles attribute invalidation and AR alias resolution on class change, then dispatches into the indexed-row fast paths.
- `active_record/record_state.rb` — Owns all per-record state: `column_indexes`, `row`, `is_indexed_row`, `attributes_hash`, `has_attributes_hash`, `types`, `additional_types`, `try_additional`, `values`. `setup(object)` returns `true` when the record class changes. `read_attribute` handles the non-indexed (Rails 7.x) fallback path.
- `active_record/context.rb` — Monkey-patches `ActiveModel::AttributeSet`, `ActiveModel::LazyAttributeSet`, `ActiveRecord::Base`, and `ActiveRecord::Result::IndexedRow` to expose `_panko_*` accessors. Defines `PANKO_INDEX_ROW_DEFINED` and `EMPTY_HASH` constants.
- `hash_writer.rb` — For Hash objects.
- `plain_writer.rb` — For plain Ruby objects.

Type-specific sub-writers for booleans, integers, floats, strings, datetimes, and JSON columns live in `active_record/values_writer/`.

**`lib/panko/object_writer.rb`** — Stack-based in-memory object builder used when the result is needed as a Ruby Hash/Array rather than a JSON string.

**`lib/panko/response.rb`** — `Response`/`ResponseCreator` compose complex nested structures; `JsonValue` embeds pre-serialized JSON strings.

### Architectural Invariants

These design decisions are intentional and must be preserved:

- **`Attribute` is AR-agnostic.** It must not reference `record_class`, AR types, or AR aliases. That logic lives in `RecordState` and `Writer`.
- **`SerializationDescriptor` is a plain data container.** It must not contain filtering logic. All filtering goes through `Panko::Filters`.
- **`RecordState` owns all per-record state.** `Writer` must not cache record-level data in its own ivars. It keeps only writer-level caches (`@column_index_cache`, `@key_cache`, etc.) and `@types_resolved`.
- **Hot paths must not allocate.** The indexed-row fast path, the ultra-fast pre-computed cache path, and the first-pass type resolution path are performance-critical. Do not add method calls, object allocations, or conditionals to these paths without benchmarking.
- **`_serialize_many` fast paths are untouchable.** They inline their work for maximum throughput. Do not extract helpers out of them.

### Performance Optimization Context

Benchmarks use `benchmark-ips` comparing against a baseline. Key strategies:
- Pre-compute everything possible into descriptors at class load time
- Inline hot-path operations to eliminate method call overhead
- Cache `column_indexes` per class for O(1) indexed row access
- Use `object.equal?(other)` identity checks (not `==`) to detect same query batch
- Access association targets directly via `association().target` to bypass Rails proxy
- Use positional args in tight loops to avoid keyword-argument overhead

Benchmark results are tracked in `benchmarks/BENCHMARKS.md`.
