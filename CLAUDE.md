# CLAUDE.md — panko_serializer

## What this project is

Panko is a fast Ruby/Rails serializer. Its public DSL — `Panko::Serializer`,
`Panko::ArraySerializer`, `scope:` / `context:`, `#serialize` /
`#serialize_to_json` — is stable and unchanged.

### Read this first: current state

This branch (`merge-scg`) has **replaced Panko's C extension with a pure-Ruby
code-generation engine**, `Panko::CodeGen` (formerly the standalone
`serializers-code-gen` gem, merged in with its full history). `Panko::CodeGen`
is now the **only** engine behind every `serialize` / `serialize_to_json` call:

- The DSL (`Panko::Serializer`) accumulates its declarations and builds an
  immutable `Panko::CodeGen::Descriptor` directly (via
  `lib/panko/code_gen/descriptor_builder.rb`); `serialize` / `serialize_to_json`
  are inlined in `Panko::Serializer` / `Panko::ArraySerializer` — each compiles
  once per (class, mode) (cached) and checks a Generated Class instance out of a
  fiber-local `InstancePool` (`SerializerCache.instance_pool`) around the call,
  releasing per-record state at checkin. `Panko::CodeGen::Runtime` only supplies
  `runtime_filters` (`only`/`except`/`filters_for` → engine `Filter` via
  `FilterAdapter`).
- The **C extension has been deleted** — `ext/` is gone and there is no native
  extension to compile. `Panko::SerializationDescriptor` and the C
  `Attribute`/`Association` classes no longer exist.

Remaining before the branch merges to `master`: **Phase 4 hardening** —
`pool_writer` default, benchmark parity/dedup, version bump + CHANGELOG, plus a
small dead-code cleanup (`Panko::ObjectWriter` is now unused).

## Repo layout

| Path | What |
|---|---|
| `lib/panko/` | Panko's DSL (`serializer.rb`, `array_serializer.rb`, `response.rb`, `serializer_resolver.rb`, …) |
| `lib/panko/code_gen.rb`, `lib/panko/code_gen/` | the code-gen engine — turns an immutable `Descriptor` into a Generated Class emitting JSON or a Hash. Now also home to the runtime seam (`runtime.rb`, `descriptor_builder.rb`, `serializer_cache.rb`, `filter_adapter.rb`). |
| `spec/features/`, `spec/unit/` | Panko's specs — run against the `Panko::CodeGen` engine |
| `spec/code_gen/` | the engine's specs — self-contained, with its own `spec_helper.rb` |
| `docs/code_gen/` | engine design docs (compilation, descriptor, filters, dumping, output-modes, …) |
| `benchmarks/` | one flattened, scenario-centric benchmark suite (`support/` harness + one file per shape) — each scenario runs `serializers_code_gen/*`, `panko/*`, `oj_serializers/*`, `plain/*` targets side by side |

## Toolchain

- **Ruby ≥ 3.4** (bumped from Panko's old 3.1 to match the engine). CI targets
  `[3.4, 4.0]`.
- **Appraisal** drives the Rails matrix via `gemfiles/{7.2.0,8.0.0,8.1.0}.gemfile`.
  Panko's *default* `Gemfile` carries **no `activerecord`**, so tests run under an
  appraisal gemfile.
- **No native extension** — the engine is pure Ruby; there is nothing to
  compile (`bundle exec rake` just runs the two spec suites).
- **lefthook** pre-commit hooks: `bundle exec lefthook install`
  (rubocop autofix + both spec lanes; no pre-push hook).
- Lint: **rubocop** (`bundle exec rubocop`), config in `.rubocop.yml`.

## Running the tests (two lanes)

The repo carries **two spec suites with separate `spec_helper.rb`s**; run them as
separate invocations under an appraisal gemfile:

```bash
# Panko's specs (codegen engine)
BUNDLE_GEMFILE=gemfiles/8.0.0.gemfile bundle exec rspec spec/features spec/unit

# code_gen engine specs (loads spec/code_gen/spec_helper.rb explicitly)
BUNDLE_GEMFILE=gemfiles/8.0.0.gemfile \
  bundle exec rspec --require ./spec/code_gen/spec_helper spec/code_gen
```

**Gotcha:** a `spec/code_gen` spec's bare `require "spec_helper"` must resolve to
`spec/code_gen/spec_helper.rb`, not Panko's `spec/spec_helper.rb`. RSpec puts
`spec/` on the load path first, so the code_gen helper prepends its own directory
to `$LOAD_PATH` to win. Do **not** run both suites in one bare `bundle exec
rspec` sweep — the two helpers conflict (Panko's re-establishes the DB
connection and clobbers the engine suite's in-memory schema).

## Conventions

- **Public API is frozen** through the merge. Preserve the `Panko::Serializer` /
  `Panko::ArraySerializer` surface, including `scope:` and `context:`.
- `Panko::CodeGen` is **internal**, not part of Panko's public surface.
- Comments explain *why*, not *what*. Keep the tree rubocop-clean.
- Commits are **local only** — the maintainer runs all `git push` / release
  steps. Never push, tag-push, or open PRs on their behalf.
