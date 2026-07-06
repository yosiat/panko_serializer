# CI and tooling

Continuous integration strategy, GitHub Actions layout, appraisal wiring for the
Rails-version matrix, and local-developer tooling (lefthook). Terms in bold are defined
in [../UBIQUITOUS_LANGUAGE.md](../UBIQUITOUS_LANGUAGE.md).

## Scope

CI verifies **correctness across the supported Ruby × Rails matrix**. It does **not**
verify performance — benchmark noise on shared runners exceeds the signal threshold this
library cares about (see [Benchmarks in CI](#benchmarks-in-ci) below).

## GitHub Actions matrix

### Cells

Two Ruby versions × three Rails versions, minus one incompatible cell. Five required
cells:

| Ruby | Rails 7.2 | Rails 8.0 | Rails 8.1 |
| ---- | :-------: | :-------: | :-------: |
| 3.4  |     ✓     |     ✓     |     ✓     |
| 4.0  |     ✗     |     ✓     |     ✓     |

**Exclusion**: `{ruby: "4.0", rails: "7.2"}`. Rails 7.2's maintenance branch predates
Ruby 4.0 and receives security fixes only — not Ruby-compatibility backports. Declared
as an `exclude:` entry on the matrix.

### Version-pinning policy — latest-in-series

`actions/setup-ruby` (or `ruby/setup-ruby`) is configured with `ruby-version: "3.4"` and
`"4.0"` — **minor-series identifiers**, not patch-level pins. Rationale:

- Patch-level drift across Ruby's security-release cadence is exactly the signal the
  matrix exists to catch. Pinning (e.g.) `4.0.2` forever defers that signal to a
  dependency bump.
- `mise.toml`'s `ruby 4.0.2` pin is for **local developer reproducibility** on the
  benchmark harness (see `docs/research/`). It has no bearing on CI — the CI workflow
  ignores it.

Rails versions are pinned via Appraisal (see [Appraisal](#appraisal)) using the
pessimistic operator `~> X.Y.0` — likewise latest-in-series within a minor.

### No `ruby-head` cell

Rejected for v1: noise from upstream Ruby main-branch churn outweighs the
early-warning value at this stage. Revisit once the library is stable enough that
a breakage signal is actionable rather than routine.

## Appraisal

[thoughtbot/appraisal](https://github.com/thoughtbot/appraisal) manages the Rails
matrix. Named appraisal groups map 1:1 to the matrix `rails` axis.

### Root `Gemfile`

Holds base dev-only deps plus a **default** `activerecord` version (latest supported)
so a fresh clone's `bundle exec rspec` works without an appraisal prefix:

```ruby
# Gemfile (illustrative)
source "https://rubygems.org"
gemspec

gem "activerecord", "~> 8.1.0"    # default; overridden by each appraisal group
gem "rspec"
gem "standard"
gem "appraisal"
gem "lefthook"
gem "oj"
gem "sqlite3"
gem "benchmark-ips"
gem "memory_profiler"
```

The gem's `.gemspec` declares **no runtime dependency on `activerecord`**. This library
*generates code* that calls `_read_attribute` on records — it does not `require
"active_record"` itself. AR is a dev-only dep used by the feature-test tier.

### `Appraisals`

One entry per matrix row. Declares `activerecord` only — not `rails` — because we test
AR-object access, not the full stack (per `testing.md`'s rationale for sqlite-in-memory):

```ruby
appraise "rails-7.2" do
  gem "activerecord", "~> 7.2.0"
end

appraise "rails-8.0" do
  gem "activerecord", "~> 8.0.0"
end

appraise "rails-8.1" do
  gem "activerecord", "~> 8.1.0"
end
```

**Future: `activesupport`** likely needs a direct dep once fixtures touch
`ActiveSupport::TimeWithZone` or similar. Add at the appraisal level when the first such
fixture lands.

### Committed gemfiles

`gemfiles/rails_7.2.gemfile`, `gemfiles/rails_8.0.gemfile`, `gemfiles/rails_8.1.gemfile`
**and their `.lock` files** are committed to the repo. Filenames preserve the dot
because Appraisal derives them via `name.gsub(/[^\w\.]/, '_')` — only non-word,
non-dot characters get replaced. Two reasons to commit:

1. **Dependabot** can update transitive deps per gemfile when locks are committed.
2. **AR version bumps are reviewable** in PR diffs, rather than invisible CI-time
   resolution.

### Matrix → appraisal wiring

```yaml
strategy:
  fail-fast: false
  matrix:
    ruby: ["3.4", "4.0"]
    rails: ["7.2", "8.0", "8.1"]
    exclude:
      - { ruby: "4.0", rails: "7.2" }

steps:
  - uses: ruby/setup-ruby@v1
    with:
      ruby-version: ${{ matrix.ruby }}
      bundler-cache: true
      # BUNDLE_GEMFILE via the appraisal wrapper
  - run: bundle exec appraisal rails-${{ matrix.rails }} bundle install
  - run: bundle exec appraisal rails-${{ matrix.rails }} rspec
```

`fail-fast: false` — one failing cell must not cancel the others; we want the full
compatibility map in one run.

## Jobs

Three jobs run in parallel on every PR. No dependency chain; fast-feedback wins over
cheaper-failure for a library-sized suite.

### Tests

- **Runs on**: every cell of the matrix (5 cells).
- **Command**: `bundle exec appraisal rails-<X> rspec`.
- **Blocks merge**: yes. No `continue-on-error` on any cell — the whole justification
  for a matrix (versus per-version adapter code, see
  [structure.md](structure.md#why-no-per-rails-version-adapter-folder)) is that each
  cell is a genuine verification.

### Lint

- **Runs on**: **one** cell (Ruby 4.0 × Rails 8.1, via appraisal).
  Linting is tool-version-sensitive, not gem-version-sensitive; running
  standardrb five times is pure waste.
- **Command**: `bundle exec standardrb`.
- **Blocks merge**: yes.
- **Rationale for standardrb over rubocop in v1**: zero-config, low friction for the
  greenfield phase. The rubocop-vs-standardrb taste debate isn't worth having on a
  pre-absorption library — at Panko-absorption time the code will be re-linted under
  Panko's rubocop config anyway. A later migration to rubocop (with `rubocop-rspec` and
  a small set of project-specific cops) is planned but out of v1 scope.

### No type-checker job

Neither Sorbet nor Steep. Reasons:

- Panko uses neither; adding types here creates cleanup at absorption.
- The public API surface is tiny and structurally enforced by `Data.define`
  (Descriptor, Attribute, MethodAttribute, Association) plus validators raising
  `DescriptorError` at construction. That's stronger and more local than RBS sigs.
- The hard part — `module_eval`'d generated source — is opaque to both tools by
  construction. Typing the scaffolding around it gives a false sense of coverage.

Type information is documented via **RDoc annotations in comments** on public methods,
with the convention that type shapes stay **stable** across versions (a breaking change
to a documented type shape is a major-version bump signal).

## Benchmarks in CI

**Not run in CI.** Runnable scripts live under `benchmarks/` (or as extensions of
`docs/research/`) with a committed baseline markdown. Benchmarks are executed on
**dev hardware** pre-release — the same pattern as `docs/research/ar_access_bench.rb`.

### Why not in CI

- **GHA-hosted runner variance** on tight Ruby loops is empirically 10–20%,
  occasionally worse on noisy-neighbor VMs. Shared CPU, no frequency-governor control,
  no NUMA pinning.
- **Regressions this library cares about** are 5–10% — exactly the band the runner
  noise floor swallows. Automated threshold-based detection (e.g.,
  `benchmark-action/github-action-benchmark` with `fail-threshold`) would either
  flag noise (false positives → signal muted) or miss real regressions (false
  negatives → no value).
- **Baseline comparability over time** matters more than per-PR automation. Fixed
  hardware means Q2 and Q4 numbers are directly comparable; GHA drift means they
  aren't.
- **Panko absorption is the endgame**. Panko has (or will have) perf infra; building a
  parallel GHA-based system here is throwaway work.

A **pre-commit sanity-benchmark hook** (lightweight canary against a committed
baseline) is punted to post-harness — see [deferred.md](deferred.md#pre-commit-sanity-benchmarks-via-lefthook).

### DB-adapter matrix (mysql/postgres) — deferred

sqlite-in-memory is sufficient for v1. The library tests AR object-access
(`_read_attribute`, `columns_hash`, `define_attribute_methods`), not SQL semantics. A
mysql/postgres matrix would verify adapter-level behavior — useful but not a blocker.
Revisit if a concrete regression motivates it. See
[testing.md § Feature-test environment](testing.md#feature-test-environment).

## Merge policy

- **Required checks**: all 5 test cells + the single lint cell. Six required checks
  in total.
- **No soft-signal jobs** in v1 — every CI job either blocks or doesn't exist. The
  discipline of "if it's not worth blocking on, it's not worth running" keeps the
  signal sharp.
- **No benchmark job**, so no benchmark-blocking decision.

## Standard hygiene

Standard GHA practices applied without separate discussion:

- **Bundler caching**: `bundler-cache: true` on `ruby/setup-ruby`. Keyed by
  `BUNDLE_GEMFILE` automatically — each appraisal group caches independently.
- **Concurrency**: `cancel-in-progress: true` on PR workflows keyed by
  `${{ github.ref }}`, so force-pushes cancel stale runs.
- **Permissions**: `contents: read` as the default workflow permission. No write tokens
  unless a specific job needs them.
- **Dependabot**: enabled for `bundler` (targets the root `Gemfile` only — see
  next bullet) and `github-actions` (targets `.github/workflows/`). Weekly schedule.
- **Dependabot does *not* scan `gemfiles/*.gemfile`**. The bundler ecosystem hard-codes
  detection to literal `Gemfile` / `gems.rb` / `*.gemspec` filenames
  ([source](https://github.com/dependabot/dependabot-core/blob/main/bundler/lib/dependabot/bundler/file_fetcher.rb)),
  and a flat `gemfiles/*.gemfile` layout is silently skipped (the only working
  workaround is one subdirectory per appraisal containing a literal `Gemfile`,
  which fights Appraisal's filename derivation). Appraisal lockfiles update
  transitively when `bundle exec appraisal install` is rerun after a root-Gemfile
  bump — i.e. dependabot opens a PR against root, an implementer pulls it locally
  and reruns `appraisal install` to refresh `gemfiles/*.gemfile.lock` before
  merging.
- **`mise.toml` ignored**: a local-dev convenience, not referenced by any workflow step.

## Local development — lefthook

[lefthook.dev](https://lefthook.dev/) manages git hooks. Committed as `lefthook.yml` in
the repo root. Install via `bundle exec lefthook install` (documented in the README's
development section).

### `pre-commit`

Two parallel steps:

1. **`standardrb --fix` on staged `*.rb` files** (auto-fix + re-stage).
   Auto-fix means the hook rarely *blocks*; it just tidies. Ruby files only, so
   editing `README.md` or a workflow file doesn't trip it.
2. **`bundle exec rspec` — full suite.**
   The suite is fast enough at v1 size that running pre-commit catches regressions
   before they reach CI, without creating `--no-verify`-level friction. If the suite
   grows slow enough to train `--no-verify` habits, scope down to the fast tiers
   (CodeBuilder + Validators + Compile-time errors) and move feature/snapshot tiers to
   CI-only.

### No `pre-push` hook

Tests already ran at pre-commit; pre-push would duplicate. Developers push WIP branches
for review and backup — a pre-push test run trains `--no-verify`, which corrupts every
other hook. Keep the hook set minimal so it stays enabled.

### Pre-commit sanity-benchmark hook — deferred

Documented in [deferred.md](deferred.md#pre-commit-sanity-benchmarks-via-lefthook).
Requires the benchmark harness, a sanity subset, and a per-dev-machine-tolerant
threshold. Not v1.
