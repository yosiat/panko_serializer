# CLAUDE.md — panko_serializer

> `AGENTS.md` is a symlink to this file so non-Claude agents read the same instructions.

## What this project is

Panko is a fast Ruby/Rails serializer. Its public DSL — `Panko::Serializer`,
`Panko::ArraySerializer`, `scope:` / `context:`, `#serialize` /
`#serialize_to_json` — is stable and unchanged.

### Architecture

Panko's serialization engine is `Panko::CodeGen`, a pure-Ruby code-generation
engine (originally the standalone `serializers-code-gen` gem, merged in with its
full history). It is the **only** engine behind every `serialize` /
`serialize_to_json` call — there is no C extension.

- The DSL (`Panko::Serializer`) accumulates its declarations and builds an
  immutable `Panko::CodeGen::Descriptor` directly (via
  `lib/panko/code_gen/descriptor_builder.rb`); `serialize` / `serialize_to_json`
  are inlined in `Panko::Serializer` / `Panko::ArraySerializer` and dispatch on
  the record's class through a one-entry inline cache backed by
  **auto-specialization** (`SerializerCache.variant_pool`): first sight of a
  named AR record class compiles a guarded Specialized variant for it (typed
  emits, `_read_attribute` reads, children filled via AR reflections); Hash
  records, POROs, compile failures, and classes past
  `Panko::Config.auto_specialization.capacity` pin to the generic base pool.
  Each variant checks a Generated Class instance out of a fiber-local
  `InstancePool` around the call, releasing per-record state at checkin.
  `Panko::CodeGen::Runtime` only supplies `runtime_filters`
  (`only`/`except`/`filters_for` → engine `Filter` via `FilterAdapter`).
- There is no C extension — no `ext/` directory and nothing to compile.
  `Panko::SerializationDescriptor` and the C `Attribute`/`Association` classes
  do not exist.

## Repo layout

| Path | What |
|---|---|
| `lib/panko/` | Panko's DSL (`serializer.rb`, `array_serializer.rb`, `response.rb`, `serializer_resolver.rb`, …) |
| `lib/panko/code_gen.rb`, `lib/panko/code_gen/` | the code-gen engine — turns an immutable `Descriptor` into a Generated Class emitting JSON or a Hash. Now also home to the runtime seam (`runtime.rb`, `descriptor_builder.rb`, `serializer_cache.rb`, `filter_adapter.rb`). |
| `spec/features/`, `spec/unit/` | Panko's specs — run against the `Panko::CodeGen` engine |
| `spec/code_gen/` | the engine's specs — self-contained, with its own `spec_helper.rb` |
| `docs/code_gen/` | engine design docs (compilation, descriptor, filters, dumping, output-modes, …) |
| `benchmarks/` | one flattened, scenario-centric benchmark suite (`support/` harness + one file per shape) — each scenario compares Panko against oj_serializers and plain Oj/`as_json` baselines; `game_serializer.rb` also pits it against alba and blueprinter, every competitor row gated on byte-identical output |

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

- **Public API is stable.** Preserve the `Panko::Serializer` /
  `Panko::ArraySerializer` surface, including `scope:` and `context:`.
- `Panko::CodeGen` is **internal**, not part of Panko's public surface.
- Comments explain *why*, not *what* — and drop a *why* that only restates a
  language/library default or an otherwise obvious fact (e.g. noting "GC stays
  enabled" when enabled is the default). Keep the tree rubocop-clean.
- **`merge-scg` is the active integration branch.** Before a large mechanical
  sweep (comment cleanup, renames, formatting), branch from / rebase onto
  `merge-scg` — not an older base like `88f5622`. It has already removed
  `docs/code_gen/research/` and `lib/panko/code_gen/validators/symbol_body_dispatch.rb`;
  editing them wastes effort and creates rebase conflicts.
- Commits are **local only** — the maintainer runs all `git push` / release
  steps. Never push, tag-push, or open PRs on their behalf.
