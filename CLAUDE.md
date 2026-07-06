# CLAUDE.md — panko_serializer

## What this project is

Panko is a fast Ruby/Rails serializer. Its public DSL — `Panko::Serializer`,
`Panko::ArraySerializer`, `scope:` / `context:`, `#serialize` /
`#serialize_to_json` — is stable and unchanged.

### Read this first: transitional state

This branch (`merge-scg`) is partway through replacing Panko's C extension with
a pure-Ruby code-generation engine, `Panko::CodeGen` (formerly the standalone
`serializers-code-gen` gem, merged in with its full history). **Two engines
currently coexist:**

- The **C extension** (`ext/panko_serializer/`) is still the *active* engine
  behind every `serialize` / `to_json` call.
- **`Panko::CodeGen`** (`lib/panko/code_gen/`) has landed with its full test
  suite but is **not yet wired into the runtime** — it runs only via its own
  specs.

The swap follows a phased plan: Phase 1 (land side-by-side) is **done**; Phase 2
replaces the C ext with codegen, Phase 3 collapses the descriptor layer, Phase 4
hardens. **Until Phase 2 lands, the C extension is the source of truth for
runtime behavior** — don't assume `Panko::CodeGen` is reachable from the DSL yet.

## Repo layout

| Path | What |
|---|---|
| `lib/panko/` | Panko's DSL & C-ext bindings (`serializer.rb`, `association.rb`, `serialization_descriptor.rb`, …) |
| `lib/panko/code_gen.rb`, `lib/panko/code_gen/` | the code-gen engine — turns an immutable `Descriptor` into a Generated Class emitting JSON or a Hash. Internal; no user DSL. |
| `ext/panko_serializer/` | the C extension (current engine; slated for deletion in Phase 2.6) |
| `spec/features/`, `spec/unit/` | Panko's specs — run against the C ext |
| `spec/code_gen/` | the engine's specs — self-contained, with its own `spec_helper.rb` |
| `docs/code_gen/` | engine design docs (compilation, descriptor, filters, dumping, output-modes, …) |
| `benchmarks/`, `benchmarks/code_gen/` | Panko's and the engine's benchmarks (dedup deferred to Phase 4) |

## Toolchain

- **Ruby ≥ 3.4** (bumped from Panko's old 3.1 to match the engine). CI targets
  `[3.4, 4.0]`.
- **Appraisal** drives the Rails matrix via `gemfiles/{7.2.0,8.0.0,8.1.0}.gemfile`.
  Panko's *default* `Gemfile` carries **no `activerecord`**, so tests run under an
  appraisal gemfile.
- The **C extension must be compiled** before Panko's specs run:
  `bundle exec rake compile`. The compiled `.bundle` is Ruby-version-specific —
  recompile after switching Ruby.
- **lefthook** pre-commit hooks: `bundle exec lefthook install`
  (standardrb autofix + both spec lanes; no pre-push hook).
- Lint: **standardrb** (`bundle exec standardrb`).

## Running the tests (two lanes)

The repo carries **two spec suites with separate `spec_helper.rb`s**; run them as
separate invocations under an appraisal gemfile:

```bash
# Panko's specs (C-ext engine)
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
- Comments explain *why*, not *what*. Keep the tree standardrb-clean.
- Commits are **local only** — the maintainer runs all `git push` / release
  steps. Never push, tag-push, or open PRs on their behalf.
