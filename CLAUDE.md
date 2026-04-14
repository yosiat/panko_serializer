# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Non-Negotiable Before Every Commit

Before committing any code change, **both** of these must pass with zero errors:

1. `bundle exec appraisal rake` — all tests across all Rails versions
2. `bundle exec rubocop` — zero offenses (use `-a` / `-A` to auto-correct)

These are equally critical. A commit with failing tests or rubocop offenses is not acceptable.

## Commands

```bash
# IMPORTANT: Always use appraisal to run tests and benchmarks.
# The main Gemfile does not include database adapters — only Appraisal gemfiles do.
# Running bare `bundle exec rake` or `bundle exec rspec` will fail with LoadError.

# Test all versions of Rails (required before every commit)
bundle exec appraisal rake

# Test against a specific Rails version (see gemfiles/ for available versions)
bundle exec appraisal <RAILS_VERSION> rake

# Run a single spec file
bundle exec appraisal <RAILS_VERSION> rspec spec/panko/serializer_spec.rb

# Regenerate gemfiles after editing Appraisals
bundle exec appraisal install

# Lint Ruby
bundle exec rubocop

# Auto-correct Ruby lint issues
bundle exec rubocop -a

# Run all benchmarks
bundle exec appraisal <RAILS_VERSION> rake benchmarks:all

# Run a specific benchmark
bundle exec appraisal <RAILS_VERSION> rake "benchmarks:run[panko_json]"

# Env vars: BENCH=pattern SIZE=N PROFILE=cpu|memory IPS_TIME=N IPS_WARMUP=N
BENCH=HasOne bundle exec appraisal <RAILS_VERSION> ruby benchmarks/panko_json.rb
SIZE=2300 bundle exec appraisal <RAILS_VERSION> ruby benchmarks/panko_json.rb
PROFILE=cpu bundle exec appraisal <RAILS_VERSION> ruby benchmarks/panko_json.rb
```

## Documentation Conventions

All public and internal methods, classes, and `attr_reader`/`attr_accessor` declarations must be documented with RDoc. Use `@param`, `@return`, and type annotations. Be specific about types. Private methods do not need RDoc unless their purpose is non-obvious.

## Architecture

Panko is a high-performance JSON serializer for ActiveRecord and Ruby objects. It compiles per-serializer classes with unrolled attribute writes at runtime, then uses `Oj::StringWriter` for JSON output or direct Hash construction for Ruby object output.

### Core Serialization Flow

```
Serializer.new(options)
  -> SerializationDescriptor.build(serializer_class)     # cached metadata
  -> Panko::Filters.apply(descriptor, options)            # :only/:except filtering
  -> descriptor.engine_serializer                         # compiled GeneratedBase subclass
  -> GeneratedBase._write_one(object, writer, filter_mask, context)
  -> Oj::StringWriter (JSON) or Hash (Ruby object output)
```

### Key Components

**`lib/panko/serializer.rb`** — Base class with DSL (`attributes`, `has_one`, `has_many`, `aliases`). Single-use by design (`@used` flag).

**`lib/panko/serialization_descriptor.rb`** — Pre-computes and caches attribute/association metadata per serializer class. `engine_serializer` returns the compiled `GeneratedBase` subclass. Delegates filtering to `Panko::Filters`.

**`lib/panko/filters.rb`** — Stateless filter engine (`Panko::Filters.apply`). Resolves `:only`/`:except` options against a descriptor.

**`lib/panko/attribute.rb`** — Represents a single serializable field. AR-agnostic — type resolution and alias lookup are handled externally.

**`lib/panko/code_gen/`** — The code generation system. See [`lib/panko/code_gen/CLAUDE.md`](lib/panko/code_gen/CLAUDE.md) for Compiler and Emitter details.

**`lib/panko/engine/attributes_writer/active_record/`** — AR record introspection layer:
- `record_state.rb` — Per-record state: `column_indexes`, `row`, types. `setup(object)` returns `true` on class change.
- `context.rb` — Monkey-patches AR internals to expose `_panko_*` accessors.
- `values_writer/` — Type-specific sub-writers (string, integer, float, boolean, datetime, json). Thread-local dispatch.

**`lib/panko/response.rb`** — `Response`/`ResponseCreator` compose complex nested structures; `JsonValue` embeds pre-serialized JSON strings.

### Architectural Invariants

- **`Attribute` is AR-agnostic.** Type resolution lives in `RecordState` and `ActiveRecordAttributesWriter`.
- **`SerializationDescriptor` is a plain data container.** Filtering goes through `Panko::Filters`.
- **`RecordState` owns all per-record state.** Writers only hold writer-level caches.
- **Hot paths must not allocate.** Do not add method calls, object allocations, or conditionals without benchmarking.
- **Code-gen rules** — see [`lib/panko/code_gen/CLAUDE.md`](lib/panko/code_gen/CLAUDE.md).
