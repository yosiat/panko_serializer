# JSON-column emit — implementation plan (S12.5 / #60)

**Status (2026-05-01)**: design proposal pending review. Implementation is
gated on three open decisions (§ 11). Once decisions are locked, the
acceptance criteria flow into [#60](https://github.com/yosiat/serializers-code-gen/issues/60)
and sandcastle picks up the implementation AFK.

**Companion docs**:
- [`docs/research/phase_1_report.md § 8.1`](phase_1_report.md) — profile findings, decision rationale
- [`docs/research/panko_behavior_diffs.md`](panko_behavior_diffs.md) — behavior changes vs Panko 0.8.5

---

## 1. Context

The `json_column` benchmark scenario fails phase-1 Clause C (allocation
parity with Panko). Today's emit on the Specialized record-access path
is:

```ruby
writer.push_value(record._read_attribute("metadata"), "metadata")
```

`push_value` in `:rails` mode dispatches to `Hash#as_json`, which walks
the typecast Hash and re-encodes every value before Oj writes the
bytes. At size=2300, this allocates 6904 objects total (~3 per record
cache-hot). Panko sits at 2320 (~1 per record).

Profiling (`PROFILE=memory`) confirmed every per-record allocation
originates in `ActiveSupport::JSON.encode`'s `Hash#as_json` walk. None
in scg's emitted code. The fix is to skip the walk entirely by reading
the pre-typecast raw String from `read_attribute_before_type_cast` and
pushing those bytes verbatim through `Oj::StringWriter#push_json` —
mirroring Panko's pure-Ruby reference branch.

## 2. Decision summary

- **Predicate**: `model.type_for_attribute(name).is_a?(::ActiveRecord::Type::Json)`
  — single line, db-agnostic, no pg-specific class references. Rejects
  `encrypts :metadata`, `serialize :m, coder:`, and `Type::Serialized`
  wrappers (all are siblings or different hierarchies, not subclasses).
- **Emit modes**: three options, behavior selected by config knob
  `json_column_emit`. Default direction is the **first open decision**.
- **Validation step**: `Oj.sc_parse(JSON_NOOP_PARSER, raw, mode: :strict)`
  with `rescue Oj::ParseError, EncodingError`. `mode: :strict` pins the
  exception class regardless of process-wide `Oj.default_options`; the
  broader rescue catches `EncodingError` raised by `:rails`/`:compat`
  modes if `mode: :strict` were ever omitted.
- **Allocation target**: ~2 allocs/record for raw-passthrough modes
  (down from ~3). The remaining alloc is the Oj sc_parse working-state
  object. Panko parity at 1 alloc/record is **not achieved** by this
  slice — closing the last alloc would require either a custom byte-scan
  validator or a `:trusted` mode that skips validation entirely.
  Out of scope for #60.

## 3. Architecture

### 3.1 File layout

| File | Change |
|---|---|
| `lib/serializers_code_gen/active_record/access_classifier.rb` | Add `json_typed?(model, name)` predicate (or extract to a sibling module) |
| `lib/serializers_code_gen/generators/field_emitters/attribute.rb` | Add `emit_json_column` method emitting the configured mode's pattern |
| `lib/serializers_code_gen/generators/record_access/specialized.rb` | Route JSON-typed Attributes through `emit_json_column` instead of `emit_json` |
| `lib/serializers_code_gen.rb` | Define `JSON_NOOP_PARSER = Object.new.freeze` |
| `lib/serializers_code_gen/config.rb` | Add `json_column_emit` and `json_column_safe_types` accessors |
| `spec/active_record/access_classifier_spec.rb` (or new) | Predicate coverage |
| `spec/features/json_column_emit_spec.rb` (new) | End-to-end emit + regression coverage |
| `spec/fixtures/generated/` | Snapshot fixtures for each mode |

### 3.2 Detection predicate

```ruby
# lib/serializers_code_gen/active_record/access_classifier.rb (or sibling)

# Returns true when +attribute_name+ on +model+ is backed by an
# ActiveRecord JSON column safe for raw-passthrough emit. Recognizes
# +ActiveRecord::Type::Json+ and any of its subclasses (notably
# +ConnectionAdapters::PostgreSQL::OID::Jsonb+ for jsonb columns).
# Sibling types like +ActiveRecord::Encryption::EncryptedAttributeType+
# and +ActiveRecord::Type::Serialized+ are correctly rejected — they
# do not inherit from +Type::Json+ (verified against AR 8.1.3).
#
# When +SerializersCodeGen.config.json_column_safe_types+ is set, the
# predicate switches to strict allowlist mode and only accepts exact
# class-name matches.
#
# @param model [Class] AR model class
# @param attribute_name [Symbol, String]
# @return [Boolean]
def self.json_typed?(model, attribute_name)
  t = model.type_for_attribute(attribute_name.to_s)
  if (allowlist = SerializersCodeGen.config.json_column_safe_types)
    allowlist.include?(t.class.name)
  else
    t.is_a?(::ActiveRecord::Type::Json)
  end
end
```

**No rescue, by design.** Empirical AR 8.1.3 audit of
`type_for_attribute(name.to_s)` returns `ActiveModel::Type::Value` (not
JSON, predicate cleanly returns `false`) for unknown attributes, `nil`
inputs, weird scalar inputs, and even after `remove_connection` once
schema is cached. The only ways it raises are
`ActiveRecord::TableNotSpecified` (abstract class) and
`ActiveRecord::StatementInvalid` (model with no underlying table) —
and both fail `AccessClassifier.classify` at `klass.columns_hash` long
before `json_typed?` runs (verified in `access_classifier.rb:111`).
Caller contract: `json_typed?` runs at compile time on a Descriptor
whose `models:` is set to a concrete, table-backed AR class. A blanket
`rescue StandardError` here would only ever swallow real bugs (typo in
predicate, AR breaking-change in a future minor). Spec coverage in
§ 7.1 pins the no-table / unknown-attribute behavior so a future AR
upgrade that flips the contract surfaces as a test failure, not silent
fallthrough.

**Why `is_a?` not `instance_of?`**: `OID::Jsonb < Type::Json` (verified
by source-read in AR 8.1.3); `is_a?` accepts both `t.json` and
`t.jsonb` without a separate class-name branch. Also accepts
user-defined subclasses of `Type::Json` (e.g., `MyApp::JsonWithLogging`).
The marginal risk — a user subclassing to override `serialize` for
encryption — is unusual and easily diagnosed; users in that situation
opt into the allowlist.

**Rejected approaches**:
- Symbol check (`column.sql_type_metadata.type == :json`): `EncryptedAttributeType`
  delegates `#type` to `:json`, predicate fires, **emits ciphertext envelope** as
  fast path (verified ciphertext leak). Rejected.
- Panko's `respond_to?(:subtype)` + symbol check: `EncryptedAttributeType`
  does NOT `respond_to?(:subtype)` (it's a sibling of `Type::Json`, not a
  Delegator), short-circuit misses, `:json` case fires, ciphertext leaks.
  Same hazard as the bare symbol check. Panko's pure-Ruby ref ships this
  bug. Rejected.

### 3.3 Config

```ruby
# lib/serializers_code_gen/config.rb

# Controls how JSON-column attributes emit on the Specialized
# record-access path. Read at compile time; changing this between
# compile() calls produces different generated code.
#
# - +:raw_passthrough+ (proposed default): fast path. Reads raw bytes
#   via read_attribute_before_type_cast, validates well-formedness via
#   Oj.sc_parse with a no-op handler, pushes them verbatim through
#   push_json. Matches Panko 0.8.5 and stdlib JSON.generate
#   byte-for-byte. Does NOT HTML-escape — defers HTML safety to the
#   consumer's HTML layer (ERB json_escape, framework auto-escape,
#   sanitizer libraries). Use when API responses go over the wire as
#   application/json.
# - +:hash_as_json+: today's behavior. Routes through Hash#as_json walk
#   and Oj :rails mode. Slow but matches ActiveSupport::JSON.encode
#   bytes exactly, including HTML-escape of <, >, &, U+2028, U+2029.
#   Use when scg's output is embedded directly in HTML script tags
#   without a sanitizer at the HTML layer (uncommon).
#
# @return [Symbol]
attr_accessor :json_column_emit

# Optional opt-in strict allowlist. When nil (default), the JSON-column
# predicate uses +is_a?(ActiveRecord::Type::Json)+ — accepts subclasses.
# When set to an Array of class-name Strings, the predicate switches to
# exact-class-name matching, rejecting all subclasses including
# +OID::Jsonb+ (so users in allowlist mode must list it explicitly).
#
# Recommended baseline allowlist:
#
#   ["ActiveRecord::Type::Json",
#    "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb"]
#
# Users can extend with custom Type::Json subclasses they trust.
#
# @return [Array<String>, nil]
attr_accessor :json_column_safe_types

def initialize
  @json_column_emit = :raw_passthrough  # proposed default — see § 11.1
  @json_column_safe_types = nil
  # ...existing...
end
```

### 3.4 Codegen

The Specialized-path generator inspects the configured `json_column_emit`
at compile time and emits one of three patterns into the generated
class. This avoids runtime branching cost — each compiled generator
embeds exactly one shape.

For an Attribute(name: `:metadata`, source: `:metadata`) on a
JSON-typed column:

#### Mode `:hash_as_json` (today's behavior)

```ruby
writer.push_value(record._read_attribute("metadata"), "metadata")
```

#### Mode `:raw_passthrough`

```ruby
raw = record.read_attribute_before_type_cast("metadata")
if raw.is_a?(String) && !raw.empty? && (begin
     Oj.sc_parse(SerializersCodeGen::JSON_NOOP_PARSER, raw, mode: :strict)
     true
   rescue Oj::ParseError, EncodingError
     false
   end)
  writer.push_json(raw, "metadata")
else
  writer.push_value(record._read_attribute("metadata"), "metadata")
end
```

The slow-path fallback (`push_value(record._read_attribute(...))`) is
identical across both modes — it handles malformed JSON, in-memory
unsaved Hash assignments, primitive non-string scalars, and any other
case where the raw bytes aren't a valid JSON String.

A `:html_safe_passthrough` mode (gsub-escape between sc_parse and
push_json) was prototyped and benchmarked — see § 5.1. The Ruby regex
engine slows down 7x when a character class contains any non-ASCII
codepoint (U+2028, U+2029), which gates the "safe" mode at < 40% of
today's throughput. Even the ASCII-only variant (`/[<>&]/` only) is
20% slower than today's `:hash_as_json`. Not viable.

## 4. Two viable emit modes — comparison

| Mode | Speed (size=2300) | Allocs/rec | HTML escape | `</`-XSS safe | Bytes match |
|---|---|---|---|---|---|
| `:hash_as_json` (today) | 797 ips (cache-hot) / 314 (cold) | ~3 (hot) / ~16 (cold) | yes | yes | AS::JSON.encode, Oj :rails, oj_serializers |
| `:raw_passthrough` (proposed) | 793 ips (hot) / 429 (cold) | ~2 (hot) / ~9 (cold) | no | no — defers to consumer's HTML layer | Panko 0.8.5, stdlib JSON.generate, Oj :strict/:compat |

A third mode `:html_safe_passthrough` (gsub-escape `<`, `>`, `&`,
optionally U+2028/U+2029, before push_json) was bench-tested and
rejected — it costs 20–64% throughput vs today depending on regex
shape. See § 5.1 for numbers and root cause.

**Cold-cache numbers matter for production framing**. The bench harness
reuses records across iterations; AR memoizes typecast on the first
read, hiding ~13 allocs/record of typecast cost. Production loads
records fresh per request and pays both. The `:raw_passthrough` and
`:html_safe_passthrough` modes are cache-independent — they never go
through the typecast path, so their numbers are identical hot vs cold.
`:hash_as_json` degrades 61% hot→cold.

## 5. Benchmark numbers

Canonical settings: `IPS_TIME=5 IPS_WARMUP=2`. Ruby 4.0.2 + YJIT, AR 8.1.3,
Oj 3.17.0, M4 Max, SQLite in-memory.

### 5.1 Cache-hot (bench harness default)

| Row | size=50 ips | size=50 allocs | size=2300 ips | size=2300 allocs | per-rec |
|---|---:|---:|---:|---:|---:|
| `scg/json` (Mode A) | 35.62K | 154 | 797 | 6904 | ~3.0 |
| `scg/json/raw+val` (Mode B) | 35.31K | 103 | 793 | 4603 | ~2.0 |
| `scg/json/raw+val+escape` (Mode C, full) | 13.02K | 153 | **288** | 6903 | ~3.0 |
| `scg/json/raw+val+escape-lite` (Mode C-lite) | 28.28K | 153 | **639** | 6903 | ~3.0 |
| `panko/json` | 31.65K | 70 | 650 | 2320 | ~1.0 |
| `oj_serializers/json` | 32.71K | 252 | 754 | 11502 | ~5.0 |

**Surprise finding**: Mode C with U+2028/U+2029 in the regex character
class hits a **7x slow path** in Ruby's regex engine — including any
non-ASCII codepoint in a character class forces per-byte unicode
matching even for ASCII input. Microbench confirmed: `/[<>&]/` runs at
7.36M ops/s, `/[<>&  ]/` runs at 1.03M ops/s on identical
ASCII input. Mode C-lite drops the U+2028/U+2029 escape and recovers
most of the perf, but **even Mode C-lite is slower than today's
`scg/json`** (639 vs 797 ips) — the gsub byte-scan costs more than
`Hash#as_json`'s walk for this fixture's small Hash. Mode C is not a
viable default.

### 5.2 Cold-cache (production-shape — `Bench::Post.instantiate(attrs_before_type_cast)` per call)

| Row | ips | allocs/rec |
|---|---:|---:|
| `scg/json` (Mode A) | 314 | 16 |
| `scg/json/raw+val` (Mode B) | 429 | 9 |
| `panko/json` | 460 | 7 |

Mode C cold-cache not measured — moot given Mode C is dead on cache-hot
perf alone.

### 5.3 Production framing

Cold-cache is the metric matching real Rails requests (records loaded
fresh per request). Mode B vs Mode A: **+36.4% ips, −43.8% allocs**.
Mode C ships ~20–64% slower than today depending on the regex shape;
not viable as a default or as a defense-in-depth opt-in worth the cost.

## 6. Behavioral parity

### 6.1 vs Panko 0.8.5

Mode B is byte-for-byte identical to Panko on the bench fixture and 11
test shapes (verified). Three documented stress cases where they diverge:

- Malformed JSON in DB: scg falls through cleanly → emits `null`. Panko
  raises (`Oj::ParseError` in `:strict` mode, `EncodingError` in
  `:rails` mode).
- In-memory unsaved Hash assignment: scg falls through cleanly. Panko
  raises `TypeError`.
- Primitive non-string scalar in DB (`42`, `true`, etc.): scg falls
  through cleanly. Panko raises `TypeError`.

Each of these is **scg degrading where Panko crashes** — strictly an
improvement. Detail in [`panko_behavior_diffs.md`](panko_behavior_diffs.md).

### 6.2 vs today's scg

Mode B produces **different bytes from today's scg** on six inputs:

| Input | Today's scg (Mode A) | Mode B (proposed) |
|---|---|---|
| `"</script>"` | `\u003c/script\u003e` | `</script>` |
| String with U+2028 | `\u2028` (escaped) |   (raw 3 bytes) |
| String with U+2029 | `\u2029` (escaped) |   (raw 3 bytes) |
| `-0.0` | `0.0` | `-0.0` |
| `1e-300` | `1.0e-300` | `1e-300` |
| `1e300` | `1.0e+300` | `1e300` |

Root cause: `ActiveRecord::Type::Json#serialize` uses
`ActiveSupport::JSON::Encoding.encode_without_escape` on write (no
HTML-escape, `Float#to_json` form), while today's `Hash#as_json → Oj
:rails push_value` does HTML-escape and uses `Float#to_s` form. The
stored bytes are already in the no-escape format; today's path adds
escape on read while Mode B preserves the stored form.

**XSS context** (load-bearing): if downstream consumers pipe scg's
JSON output to HTML-injecting framework primitives (`innerHTML`,
`v-html`, Vue/Angular/React equivalents) without sanitization, Mode B
loses the HTML-escape safety net that today's path accidentally
provides. The user's responsibility to sanitize at the HTML layer
(ERB `json_escape`, framework auto-escape, sanitizer libraries) is
unchanged — but if they were depending on scg's output being inert in
HTML contexts, that contract is silently broken on upgrade. Document
prominently in migration notes.

In the broader Ruby ecosystem, the split is 5/5: standards-flavored
serializers (Panko, stdlib `JSON.generate`, `Oj.dump(:strict)`,
`Oj.dump(:compat)`) don't escape; Rails-flavored serializers
(`ActiveSupport::JSON.encode`, `Oj :rails`, `oj_serializers`) do.
Mode B picks the standards-flavored half.

### 6.3 Inherited Panko behavior

In-place mutation (`record.metadata["new"] = "v"` without save): Mode
B emits pre-mutation bytes (raw bytes are unchanged by the typecast
Hash mutation). Today's Mode A emits post-mutation bytes (reads
through `_read_attribute` which returns the mutated Hash). This is
**inherited from Panko** — Mode B matches Panko; today's scg is the
divergent path. Inherited Panko contract: callers that mutate the
typecast Hash must reassign or call `metadata_will_change!`.

### 6.4 Multi-DB

Predicate fires correctly for:
- SQLite `t.json` → `Type::Json`
- MySQL `t.json` (Rails 7+) → `Type::Json`
- Postgres `t.json` → `Type::Json`
- Postgres `t.jsonb` → `OID::Jsonb < Type::Json`

`read_attribute_before_type_cast` returns raw String on every adapter
(no driver-level JSON-to-Hash coercion installed by AR or pg/mysql2).

## 7. Test coverage (TDD spec plan)

### 7.1 Predicate spec (`spec/active_record/access_classifier_spec.rb`)

- `t.json` column → returns true
- `t.jsonb` column (Postgres-only — skip on SQLite, but test class hierarchy via `attribute :m, OID::Jsonb.new`) → returns true
- `encrypts :m` → returns false (with AR encryption keys configured)
- `serialize :m, coder: Marshal` → returns false
- `serialize :m, coder: YAML` → returns false (or skip if Rails 8.1 raises `ColumnNotSerializableError`)
- `t.string :m` → returns false
- Custom `class MyJson < Type::Json` (default config) → returns true
- Custom `class MyJson < Type::Json` with allowlist mode → returns false unless added
- No-column case (`columns_hash[name].nil?`) → returns false
- `attr_encrypted :m` (third-party gem) — skipped if gem not in bundle

### 7.2 Codegen spec (`spec/generators/json_column_emit_spec.rb`)

For each mode:
- Generated source contains the expected primitive (`push_value` for Mode A, `push_json` + `Oj.sc_parse` for Mode B)
- Snapshot fixture under `spec/fixtures/generated/`

### 7.3 Behavior spec (`spec/features/json_column_emit_spec.rb`)

For Mode B (`:raw_passthrough`):
- Happy path: `t.json` Specialized descriptor with metadata Hash → byte-identical to expected output
- Malformed JSON in DB (raw SQL update): falls through, emits `null`
- In-memory unsaved Hash assignment: falls through, byte-identical to today
- Primitive non-string scalar in DB: falls through, emits the scalar
- In-place mutation: emits stale pre-mutation bytes (pinned as inherited Panko behavior)

For Mode A (`:hash_as_json`, today's): one snapshot regression spec
confirming bytes match today's output across the same fixtures. Acts
as a frozen baseline.

### 7.4 Allocation regression spec

Pin the allocation invariant via MemoryProfiler in-spec:

```ruby
it "Mode B allocates < 2.5 allocs per record at size=2300" do
  records = Bench::Post.first(2300)
  allocs = MemoryProfiler.report { generator.serialize_many(records) }.total_allocated
  expect(allocs).to be < 2.5 * records.size  # ~2 allocs/record + small overhead
end
```

Or pin against Panko: `expect(scg_allocs).to be <= panko_allocs * 2`.

### 7.5 Encryption-specific spec

Confirm that `encrypts :metadata` does NOT route through the fast path:

```ruby
it "does not emit ciphertext for encrypted attributes" do
  EncryptedPost.create!(metadata: {"k" => "v"})  # encrypts :metadata
  output = scg_serializer.serialize(EncryptedPost.first)
  expect(output).to include('"metadata":{"k":"v"}')  # decrypted plaintext
  expect(output).not_to include('"p":')  # no AR encryption envelope marker
end
```

This is the **load-bearing safety test**. Must pass.

## 8. Implementation steps

1. Add config knobs in `config.rb` (defaults TBD per § 11).
2. Add `JSON_NOOP_PARSER = Object.new.freeze` constant in `lib/serializers_code_gen.rb`.
3. Add `json_typed?` predicate to access_classifier (or sibling).
4. Wire predicate into `Specialized` record-access path: when JSON-typed,
   route Attribute through new `emit_json_column` method.
5. Add `emit_json_column` to `field_emitters/attribute.rb` — emits the
   pattern matching `config.json_column_emit`.
6. Snapshot fixtures under `spec/fixtures/generated/`.
7. Spec coverage per § 7.
8. Re-run canonical `rake bench:all` — update `phase_1_report.md § 3.1.6`
   numbers and § 4.1's `json_column` Clause C row to "Yes". Verdict in
   § 1 flips from `fail` to `pass`.
9. § 8.1 closeout block records implementation commit SHA, re-run
   excerpt, allocation delta vs pre-fix baseline.

## 9. Documentation

- Update `phase_1_report.md § 8.1` per § 11 once decisions land.
- Migration note in `docs/` (or wherever — TBD): default emit changes
  produce different bytes for `</`, U+2028, U+2029, `-0.0`, exponent
  floats. Same scale-of-change as the prior Hash-mode key-type flip.
- RDoc on every new public method/constant per project doc style.

## 10. Out of scope

- **Bar tuning**. No `phase-1-bar.md` changes.
- **Generic record-access path** (`models: nil` Descriptors). JSON-column
  optimization is Specialized-path only.
- **Closing the last alloc to Panko parity**. Mode B and Mode C sit at
  ~2 allocs/record vs Panko's ~1. The remaining alloc is Oj's sc_parse
  working state. Closing it requires either a custom byte-scan validator
  or a `:trusted` mode that skips validation entirely. File as a separate
  slice if needed.
- **Per-attribute config**. The emit mode is process-wide, set at boot
  before any `compile()` call. Per-attribute or per-Descriptor overrides
  are out of scope.
- **Bench-honesty improvements** (cold-cache as the canonical metric).
  Today's bench is cache-flattered; a separate slice could address bench
  methodology. The cold-cache run included here is for production framing
  only, not a replacement for the canonical bench.

## 11. Open decisions (to lock before implementation)

### 11.1 Default emit mode

Two viable options:

- **`:raw_passthrough`** — pure perf, byte-parity with Panko and stdlib
  `JSON.generate`. Defers HTML safety to the consumer's HTML layer
  (ERB `json_escape`, framework auto-escape, sanitizer libraries, etc.).
  Matches the perf reason scg exists. **Cost**: existing consumers
  who pipe scg output to HTML-injecting framework primitives without
  sanitization lose the accidental HTML-escape safety net (silent
  behavior change on upgrade).
- **`:hash_as_json`** — preserves today's bytes exactly. Zero risk of
  regressing existing consumers' behavior. **Cost**: loses the entire
  optimization (#60's reason for existing).

A third option `:html_safe_passthrough` was prototyped, benchmarked,
and rejected — costs 20% throughput with minimal benefit (Ruby regex
slow path on multi-byte char-classes, gsub byte-scan cost on small
fixtures). See § 5.1.

**Recommendation: `:raw_passthrough` default, with a prominent
migration note.** Justification:

1. Perf is why scg exists — defaulting to `:hash_as_json` ships #60 as
   a no-op slice.
2. The XSS exposure on upgrade is bounded: consumers must
   (a) consume scg's JSON output, (b) embed values in HTML contexts
   without sanitization, AND (c) have JSON-column data that contains
   HTML-special characters they don't control. The third condition is
   the load-bearing one — most JSON-column data is server-controlled
   (config, structured records) or comes from inputs already
   sanitized at the form layer. Consumers running user-provided
   freeform text through JSON columns AND piping it to innerHTML
   without sanitization have an XSS vector regardless of which JSON
   serializer they use.
3. The Ruby ecosystem split is 5/5 — scg picks the
   standards-flavored half (Panko, stdlib, Oj :strict).
4. Migration is a one-flag flip for users who need the old behavior.

If this trade-off feels wrong, default to `:hash_as_json` and document
`:raw_passthrough` as opt-in for performance. The user-facing config
shape is identical either way; only the default value changes.

### 11.2 `json_column_safe_types` allowlist exposure

Ship the config knob (as documented in § 3.3) or omit it for now and
add later if a user requests it? Leaning toward shipping — costs nothing
to define, gives users an escape hatch for security-paranoid setups
without coupling them to scg's internal predicate logic.

### 11.3 Migration / docs strategy

If the default emit mode produces different bytes from today's scg
(Modes B and C both do), where does the "behavior change" notice live?
Options:
- Inline note in `phase_1_report.md § 8.1`
- Top-level `CHANGELOG.md` entry (none exists yet)
- A migration doc neighbor of `panko_behavior_diffs.md`
- Just a release-notes paragraph on the implementation PR

Lowest-friction: add a sentence in `panko_behavior_diffs.md` overview
linking to `phase_1_report.md § 8.1` for the design rationale, and put
the user-facing migration note on the PR.

---

## Quick-reference: what sandcastle needs

When the three open decisions are locked, the implementer agent needs:

1. The default value for `config.json_column_emit` (Decision 11.1)
2. Whether to ship `config.json_column_safe_types` (Decision 11.2)
3. Where to put the migration note (Decision 11.3)

Everything else in §§ 3, 7, 8 is locked-decision implementation work.
