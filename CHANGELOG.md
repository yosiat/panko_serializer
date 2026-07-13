# Changelog

## Unreleased

Panko's serialization engine has been rewritten. The C extension is gone;
every `serialize` / `serialize_to_json` call now runs on `Panko::CodeGen`, a
pure-Ruby code-generation engine that compiles each serializer into
specialized, straight-line Ruby once and reuses it. The public API —
`Panko::Serializer`, `Panko::ArraySerializer`, the DSL, filters, `context` /
`scope`, `Panko::Response` — is unchanged, and matching the old engine's JSON
output byte-for-byte was a design gate for the rewrite; the few deliberate
divergences are called out under Breaking changes.

### Breaking changes

- **Ruby >= 3.4 is required** (previously 3.1).
- **ActiveSupport >= 7.2 is required.** Rails 7.2, 8.0, and 8.1 are tested in
  CI.
- **The C extension and its classes are gone.** `Panko::SerializationDescriptor`,
  `Panko::Attribute`, `Panko::Association`, and `Panko::ObjectWriter` no longer
  exist. None of these were part of the documented API, but code reaching into
  them will break.
- **Attribute values are read through ActiveRecord itself.** The C extension
  implemented its own type casting over raw column values; the new engine
  reads attributes the way the rest of your app does, so every value matches
  `record.<attribute>` exactly — including custom attribute types, enums, and
  time-zone-aware attributes. Code that depended on an edge case of the C
  extension's own casting may see different values.
- **Attribute sources must resolve to a column or a method.** The old engine
  read attributes only from the ActiveRecord attribute set: a declared
  attribute missing from it — a typo, a column that exists on a sibling
  model — silently serialized as a permanent `null`, and model instance
  methods were never consulted. The new engine dispatches like regular Ruby:
  an instance method now serializes its return value where the old engine
  wrote `null`, and a source that is neither a column nor a method raises —
  `Panko::CodeGen::UnknownSourceError` at compile time on the specialized
  path, `NoMethodError` from `record.<source>` on the generic path. To keep
  emitting a `null` key on the wire, define the method and return `nil`.
- **Declaring the same name as both an attribute and an association raises.**
  The old engine silently wrote both keys into the JSON — the attribute
  first, then the association — so JSON parsers kept the association value
  (last key wins). The new engine rejects the serializer with
  `Panko::CodeGen::NameCollisionError` when it is first compiled. Drop the
  attribute declaration to keep the old parsed output.
- **`serialize_to_json` output no longer ends with a newline.** The old
  engine returned `Oj::StringWriter` output verbatim, which always carried a
  trailing `"\n"`. Parsed JSON is identical; only byte-level consumers —
  response caches, checksums, ETags — see the one-byte difference.
- **Runtime association sub-filters compose with declared filters instead of
  replacing them.** When a runtime sub-filter (`only: {comments: [...]}`) was
  present, the old engine rebuilt that association from the child
  serializer's full field set, discarding the association's declared
  `only:` / `except:`. The new engine bakes declared filters into the
  association and applies the runtime sub-filter on top, so the result is
  the intersection — a runtime sub-filter can narrow an association further
  but can no longer resurrect fields its declaration filtered out. Widen or
  drop the declared filter to restore the old output.
- **A nested serializer's `filters_for` no longer overrides runtime
  sub-filters.** On a colliding `only:` / `except:` key the old engine let
  the child's `filters_for` win — a runtime `only: {users: [:name]}` was
  silently discarded when `UserSerializer.filters_for` returned its own
  `only:`. The new engine evaluates a nested serializer's `filters_for` once,
  at declaration time (with `nil` context and scope), and intersects runtime
  sub-filters with it, same as the previous bullet. Non-colliding
  combinations behave as before.

### Added

- **Auto-specialization.** The first time a serializer meets an ActiveRecord
  class, Panko compiles a variant hard-wired to that model — typed column
  reads straight from attribute storage, associations resolved through the
  model's reflections — guarded by an `instance_of?` check so heterogeneous
  collections, plain Hashes, and POROs stay correct on the generic path.
  Automatic, bounded, and tunable.
- **`Panko.configure` / `Panko::Config`.** Runtime configuration for
  auto-specialization: `auto_specialization.enabled` (default `true`) and
  `auto_specialization.capacity` (default 16 variants per serializer class and
  output mode).
- **`Panko::CodeGen.dump`.** Writes the generated Ruby source for a serializer
  to a file — the engine emits plain, readable Ruby, and you can look at it.
- **`Panko::Descriptor`.** A public, read-only view of a serializer's shape —
  attributes, method attributes, and associations, with nested descriptors —
  for tooling such as association preloaders. `PostSerializer.descriptor`
  returns the declared shape; `serializer.descriptor` returns the effective
  shape for that instance, honoring `only` / `except` / `filters_for`. The
  unfiltered view is cached and allocation-free to read; filtered views
  resolve lazily, and the serialization hot path is unaffected either way.
- **Instance and writer pooling.** Serialization checks generated-class
  instances and `Oj::StringWriter`s out of fiber-local pools, so steady-state
  JSON serialization allocates a near-constant handful of objects regardless
  of collection size.

### Changed

- **Faster.** Generated straight-line Ruby, specialized per record class and
  compiled by YJIT, beats the 0.8.5 C extension on every benchmark. A paired
  head-to-head (both versions on the same Ruby 4.0.2 + YJIT) measures roughly
  **1.9x** faster on JSON output and **3.1x** on Hash output (geomean across
  Panko's suite), while allocating far fewer objects — steady-state JSON stays
  O(1) in allocations where the C extension grew per record.
- **Nothing to compile at install.** The gem is pure Ruby — installation no
  longer builds a native extension.
- **Documentation rewritten** at [panko.dev](https://panko.dev), including the
  engine's design docs in `docs/code_gen/`.
