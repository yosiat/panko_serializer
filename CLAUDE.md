# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run tests (compiles C extensions first, then runs specs)
bundle exec rake

# Run only specs
bundle exec rake spec

# Run a single spec file
bundle exec rspec spec/panko/serializer_spec.rb

# Lint Ruby
bundle exec rake rubocop

# Auto-correct Ruby lint issues
bundle exec rubocop -a

# Compile C extensions
bundle exec rake compile

# Run benchmarks
bundle exec rake benchmarks:sanity
bundle exec rake benchmarks:all

# Test against a specific Rails version (uses Appraisal)
bundle exec appraisal 7.1.0 rake

# Regenerate gemfiles after editing Appraisals
bundle exec appraisal install
```

## Architecture

Panko is a high-performance JSON serializer for ActiveRecord and Ruby objects. It pre-computes serialization metadata at class load time and uses `Oj::StringWriter` for incremental JSON generation.

### Core Serialization Flow

```
Serializer.new(options)
  → SerializationContext.create(options)
  → SerializationDescriptor.build(serializer_class)   # cached metadata
  → Panko::Impl::Serializer
  → AttributesWriter (AR/Hash/Plain depending on object type)
  → Oj::StringWriter (JSON output)
```

### Key Components

**`lib/panko/serializer.rb`** — Base class with DSL (`attributes`, `has_one`, `has_many`, `aliases`). Stores class-level metadata. Single-use by design (`@used` flag).

**`lib/panko/serialization_descriptor.rb`** — Pre-computes and caches attribute/association metadata. Handles `only`/`except` filtering and propagates context/scope through association chains.

**`lib/panko/impl/serializer.rb`** — The hot-path serialization engine. Contains multiple fast paths:
- Ultra-fast: attributes only, no methods/associations
- Fast: attributes + has_one
- Full: attributes + methods + associations

Optimized to inline method calls, use positional args, and bypass Rails association proxies (`association().target` instead of `public_send`).

**`lib/panko/impl/attributes_writer/`** — Type-specific writers selected at runtime:
- `active_record/writer.rb` — Uses `column_indexes` for direct indexed row access, avoiding ActiveRecord attribute overhead
- `hash_writer.rb` — For Hash objects
- `plain_writer.rb` — For plain Ruby objects

Type-specific sub-writers for booleans, integers, floats, strings, datetimes, and JSON columns live in `active_record/values_writer/`.

**`lib/panko/object_writer.rb`** — Stack-based in-memory object builder used when the result is needed as a Ruby Hash/Array rather than JSON string.

**`lib/panko/response.rb`** — `Response`/`ResponseCreator` compose complex nested structures; `JsonValue` embeds pre-serialized JSON strings.

**`ext/panko_serializer/`** — Minimal C extension (~224 lines). Only handles DateTime/Time conversion optimizations (`time_conversion.c`).

### Performance Optimization Context

The `ruby-impl-perf` branch is an active performance optimization effort. Benchmarks use `benchmark-ips` comparing against a baseline. Key strategies in the codebase:
- Pre-compute everything possible into descriptors at class load time
- Inline hot-path operations to eliminate method call overhead
- Cache `column_indexes` per class to skip `object.class` checks on batch paths
- Access association targets directly via `association().target` to bypass Rails proxy
- Use positional args in tight loops

Benchmark results are tracked in `benchmarks/BENCHMARKS.md`.
