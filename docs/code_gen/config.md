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
`"latest_post"`).

### `hash_record_key_type` (default: `:string`)

Controls the lookup form emitted in `_write_one_hash` when the **Record** is a Hash
(generic path only — the specialized path contractually assumes instances of the declared
**Models**, not Hashes).

- `:string`: emits `record["id"]`. Matches `JSON.parse` output and Panko's current convention.
- `:symbol`: emits `record[:id]`. Matches Ruby literal hashes and ActionController params.

The choice is baked into the helper at **Compile** time — one monomorphic lookup form per
class. Mixed-key Hashes (both `"id"` and `:id`) are not supported; callers normalize upstream
if needed.

## What belongs in Config vs elsewhere

- **Compile-time toggles that change emitted code** → Config.
- **Values supplied per call** → method kwargs on the **Generated Class**.
- **Descriptor-level facts** (e.g., **Models**) → the **Descriptor** itself.

## Immutability

Config is a frozen `Data` value. No library-wide mutable singleton. No `SerializersCodeGen.configure { ... }`
block. If a caller wants a shared default **Config**, they keep their own constant.

This avoids the class of bug where a global mutable config change invalidates cached
**Generated Classes** held elsewhere.

## Future fields (not yet decided)

Candidates under discussion — see [open-questions.md](open-questions.md):

- `hash_key_type: :string | :symbol` for Hash-mode *output* key format (distinct from
  `hash_record_key_type`, which is about reading Hash Records on the generic path).
- Filter-related toggles.
