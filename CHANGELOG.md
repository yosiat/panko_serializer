# Changelog

## Unreleased

Panko's serialization engine has been rewritten. The C extension is gone;
every `serialize` / `serialize_to_json` call now runs on `Panko::CodeGen`, a
pure-Ruby code-generation engine that compiles each serializer into
specialized, straight-line Ruby once and reuses it. The public API —
`Panko::Serializer`, `Panko::ArraySerializer`, the DSL, filters, `context` /
`scope`, `Panko::Response` — is unchanged, and matching the old engine's JSON
output byte-for-byte was a design gate for the rewrite.

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
- **Instance and writer pooling.** Serialization checks generated-class
  instances and `Oj::StringWriter`s out of fiber-local pools, so steady-state
  JSON serialization allocates a near-constant handful of objects regardless
  of collection size.

### Changed

- **Faster.** Generated straight-line Ruby, specialized per record class and
  compiled by YJIT, outperforms the 0.8.5 C extension by roughly 2–3x on
  Panko's own benchmark suite (Ruby 4.0.2 + YJIT; see `benchmarks/`).
- **Nothing to compile at install.** The gem is pure Ruby — installation no
  longer builds a native extension.
- **Documentation rewritten** at [panko.dev](https://panko.dev), including the
  engine's design docs in `docs/code_gen/`.
