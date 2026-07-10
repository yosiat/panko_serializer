# Config

The **Config** is a compile-time settings struct passed to **Compile**. Its values are
baked into the emitted code — no runtime branching for configured behaviors.

## Shape

```ruby
module SerializersCodeGen
  Config = Data.define(
    :null_for_missing_has_one,   # Boolean; default: true
    :supports_root_key,          # Boolean; default: false
    :hash_record_key_type,       # :string | :symbol; default: :string — generic path only
    :hash_output_key_type,       # :string | :symbol; default: :string — Hash mode output
    :json_column_emit,           # :wire_format | :html_safe; default: :wire_format — JSON-column emit shape
    :pool_writer,                # Boolean; default: true — JSON-mode Writer pooling
    # Additional knobs to be added as design proceeds
  )
end
```

All fields default to sensible values so most callers can omit the config entirely
(`SerializersCodeGen.compile(descriptor, output: :json)`).

## Fields

### `null_for_missing_has_one` (default: `true`)

When a `has_one` **Association**'s **Source** method returns `nil`:

- `true` (default): write the key with `null` / `nil` value in the output.
- `false`: omit the key entirely.

No runtime cost — the emitted code branch is chosen at **Compile** time.

### `supports_root_key` (default: `false`)

Controls whether the **Generated Class** supports per-call **Root Key** wrapping.

- `false`: the `serialize_one` / `serialize_many` methods have no `root_key:` kwarg. Passing
  one raises `ArgumentError`. Zero runtime overhead.
- `true`: the methods gain a `root_key:` kwarg defaulting to `nil`. When truthy, the output
  is wrapped with that string key. One branch per call.

The caller supplies the wrapping key at call time, not at **Compile** time — so one
**Generated Class** can serve multiple endpoints with different wrappers (e.g., `"post"` vs
`"latest_post"`). The key must be a non-empty String or `nil`; empty String, Symbol, or
any other value raises `ArgumentError` at call time. See
[generated-class.md](generated-class.md) for the full kwarg contract.

### `hash_record_key_type` (default: `:string`)

Controls the lookup form emitted for Hash **Records** — the `record.is_a?(Hash)` arm of
`_write_one` / `_to_hash`, or the per-shape Hash helper above the fused-dispatch
threshold (generic path only — the specialized path contractually assumes instances of
the declared **Models**, not Hashes).

- `:string`: emits `record["id"]`. Matches `JSON.parse` output and Panko's current convention.
- `:symbol`: emits `record[:id]`. Matches Ruby literal hashes and ActionController params.

The choice is baked in at **Compile** time — one monomorphic lookup form per class. Mixed-key Hashes (both `"id"` and `:id`) are not supported; callers normalize upstream
if needed.

### `hash_output_key_type` (default: `:string`)

Controls the key type emitted in the **Hash Output Mode** output. Applies uniformly to
every **Field** — **Attributes**, **Method Attributes**, and **Associations** — at every
nesting depth.

- `:string`: emits `result["id"] = ...`. Matches Panko, JSON round-tripping, and
  `as_json`. Keys are frozen string literals under `frozen_string_literal: true`.
- `:symbol`: emits `result[:id] = ...`. Symbols in Ruby are always interned; symbol
  literals from emitted source are always frozen.

Uniformity across the tree is a consequence of **Compile** propagating the same **Config**
to every nested **Descriptor** it compiles. Do not mix `hash_output_key_type` values across
a parent and its nested **Generated Classes** by manually re-compiling with a different
**Config** — the output will have inconsistent key types and round-trip behavior will
break. (The library does not enforce this at runtime; it's a caller contract.)

No effect on **JSON Output Mode** — JSON keys are always strings per the spec.

### `json_column_emit` (default: `:wire_format`)

Controls how AR `:json`- and `:jsonb`-column **Attributes** emit on the **Specialized
path** in **JSON Output Mode**. Read at **Compile** time; each **Generated Class** embeds
exactly one shape.

- `:wire_format` (default): reads the raw stored bytes via
  `read_attribute_before_type_cast`, validates well-formedness via `Oj.sc_parse(mode: :strict)`
  with a no-op handler, pushes them verbatim through `Oj::StringWriter#push_json`. Matches
  Panko 0.8.5 byte-for-byte. Does **not** HTML-escape `<` / `>` / `&` or U+2028 /
  U+2029 — defers HTML safety to the consumer's HTML layer.
- `:html_safe`: routes through `Hash#as_json` and Oj `:rails` mode. HTML-escapes `<` /
  `>` / `&` and U+2028 / U+2029 the way `ActiveSupport::JSON.encode` does. Roughly 36%
  slower in production-shape (cold-cache) conditions and produces ~2× the allocations of
  `:wire_format`.

The default presumes Panko-mediated access (the only access pattern this gem supports per
its gemspec metadata). `:html_safe` exists for the case where scg's output is embedded
directly in HTML script tags without a sanitizer at the HTML layer (uncommon).

Detection of JSON-typed columns uses `is_a?(::ActiveRecord::Type::Json)` —
adapter-agnostic; matches `t.json` and `t.jsonb` on every supported backend; correctly
rejects `encrypts :metadata` (sibling type, not a subclass) and `serialize :m, coder:`
(also a sibling). Generic-path **Descriptors** (`models: nil`) are unaffected — the knob
applies only to the **Specialized path**.

Design rationale, byte-divergence table, and benchmark numbers:
[`docs/research/phase_1_report.md § 8.1`](research/phase_1_report.md).

### `pool_writer` (default: `true`)

Controls whether the **JSON Output Mode** emit reuses **Writers** across `serialize_one` /
`serialize_many` calls via a per-**Generated Class** fiber-local LIFO pool. See
[output-modes.md § Writer lifecycle](output-modes.md#writer-lifecycle) for the lifecycle
contract and [`lib/serializers_code_gen/writers_pool.rb`](../lib/serializers_code_gen/writers_pool.rb)
for the pool implementation.

- `true` (default): the **Generated Class** declares
  `POOL = SerializersCodeGen::WritersPool::<backend>.new(:<unique_key>)` as a class-level
  constant; `serialize_one` / `serialize_many` open with `writer = POOL.checkout`, wrap
  the body in `begin` / `ensure`, and return the **Writer** via `POOL.checkin(writer)`
  in the `ensure`. After warmup, `checkout` allocates zero objects on the steady-state
  hot path. The `<backend>` is `WritersPool::IsolatedExecutionState` when
  `ActiveSupport::IsolatedExecutionState` is defined at **Compile**, otherwise
  `WritersPool::ThreadLocal` — chosen once and baked in as a literal class name.
- `false`: emits the byte-identical pre-pooling source — `writer =
  Oj::StringWriter.new(mode: :rails)` inline, no `POOL` constant, no `begin`/`ensure`
  wrap. Intended as an emergency rollback path, a debugging affordance, or for
  ABI-strict callers who need the exact pre-S16 emit shape.

When to flip to `false`: production rollback if a pool-related defect surfaces, local
debugging where every-call-allocates makes leak / state-corruption hypotheses easier to
isolate, or callers (e.g., test harnesses) that depend on the pre-pooling source bytes.
Pooled and unpooled emits produce **byte-identical JSON output** for every (fixture,
mode) pair — flipping the knob is a one-line **Config** change with no observable output
difference.

No effect on **Hash Output Mode** — Hash mode allocates no **Writer** and the knob is a
no-op there.

## What belongs in Config vs elsewhere

- **Compile-time toggles that change emitted code** → Config.
- **Values supplied per call** → method kwargs on the **Generated Class**.
- **Descriptor-level facts** (e.g., **Models**) → the **Descriptor** itself.

## Immutability

Config is a frozen `Data` value. No library-wide mutable singleton. No `SerializersCodeGen.configure { ... }`
block. If a caller wants a shared default **Config**, they keep their own constant.

This avoids the class of bug where a global mutable config change invalidates cached
**Generated Classes** held elsewhere.

## Future fields

No additional fields are currently planned. In particular, filter-related toggles
are explicitly **not** planned — filters are a default feature, unconditional.
See [filters.md](filters.md).
