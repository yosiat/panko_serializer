# Deferred

Items explicitly punted out of v1, with the version or milestone they're deferred to. When
reviving one, check that the corresponding section of the main docs still holds.

## v2

### Polymorphic Associations

**Feature**: an **Association** whose target **Descriptor** varies per row based on the
**Record** class (e.g., `Post has_many :attachments` where rows can be `Image`, `Video`, or
`Pdf`).

**Why punted**: requires a new **Descriptor** field shape — either a dispatch map
`{ Image => ImageDescriptor, Video => VideoDescriptor }` or a dispatching **Callable**.
Non-trivial design and not a blocker for Panko's common cases.

**How to apply when revived**: add a new **Association** variant or a new field
`polymorphic_descriptors:` on **Association**. Emit a runtime `case record.class` in the
generated code. Keep monomorphism intact for the non-polymorphic case (zero cost when unused).

### `json_column_safe_types` allowlist

**Feature**: an opt-in **Config** field flipping the JSON-column detection predicate from
subclass-friendly (`is_a?(::ActiveRecord::Type::Json)`) to exact-class-name allowlist
matching. Lets a maintainer narrow the fast path — rejecting trusted subclasses by default
and only accepting class names they've explicitly listed.

**Why punted**: scg's `:wire_format` default already matches Panko 0.8.5 byte-for-byte
today, so the allowlist is purely defense-in-depth against a hypothetical unsafe
`Type::Json` subclass. The known siblings of `Type::Json` (`EncryptedAttributeType`,
`Type::Serialized`) are correctly rejected by the default predicate; the only known
subclass (`OID::Jsonb`) is verified safe. No real subclass risk in the wild and no user
requesting the knob — adding API surface for a hypothetical future maintainer-self is
YAGNI.

**How to apply when revived**: add `json_column_safe_types: nil` to the **Config**
`Data.define` shape. Branch the JSON-column predicate: when set, use
`allowlist.include?(type.class.name)` instead of `is_a?`. Recommended baseline allowlist
matching today's `is_a?` behavior:

```ruby
[
  "ActiveRecord::Type::Json",
  "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb"
]
```

### Fully self-contained Dumps

**Feature**: a **Dump**ed `.rb` file with **Callable** source inlined, requiring zero
runtime **Descriptor** to run.

**Why punted**: requires Proc source recovery via `method_source` gem. Works for real
`def` methods and simple lambdas; fails for dynamically-built callables. Scope and failure
modes need more thought. Not a blocker for debugging — the descriptor-at-init form is
already readable.

**How to apply when revived**: add `dump(descriptor, output:, inline_callables: true)`.
Walk the **Descriptor**'s callables, attempt `method_source` recovery; emit inline lambda
source where possible, fall back to a comment placeholder otherwise.

## Post-benchmark

### Pre-commit sanity benchmarks via lefthook

**Feature**: a lefthook `pre-commit` hook that runs a small, fast subset of the
benchmark harness and flags regressions vs. a committed baseline before the commit
lands. Intended as a first-line-of-defense against accidental perf regressions — the
CI tier explicitly won't run benchmarks (GHA noise floor > our signal threshold; see
[benchmarks.md](benchmarks.md)).

**Why punted**: depends on the full benchmark harness landing first (harness, baseline
file format, comparison tool). Also needs a "sanity subset" concept — the smallest
selection of benchmarks that still catches regressions — so the hook stays sub-second
and doesn't train people to `--no-verify`. Premature without the harness.

**How to apply when revived**:
1. Define a sanity subset under `benchmarks/sanity/` — 2–3 micro-benchmarks on the
   hot paths (e.g., `_read_attribute` dispatch, `_write_one` on a shallow model).
2. Commit baseline numbers alongside the scripts (reproducible on the dev hardware
   the benchmarks were recorded on — matches the `docs/research/` pattern).
3. Add a `pre-commit` hook entry in `lefthook.yml` that runs the subset and compares
   against the baseline; allow `LEFTHOOK=0` / `--no-verify` escape hatch without
   apology (noisy dev machines are a real case).
4. Keep the threshold generous (e.g., 25% regression) to avoid per-machine variance
   tripping developers. This hook is a canary, not a gate — CI is the gate (for
   correctness), and the release-time manual benchmark run on fixed hardware is
   the authoritative perf record.

## No fixed revisit date

### `if:` / `unless:` on Attributes and Method Attributes

**Feature**: per-row conditional inclusion for non-**Association** fields.

**Why punted**: adds complexity to the **Generator**, and the use case is partially covered
by **Method Attributes** returning `SKIP`. User wants to explore alternative primitives
before adding.

**How to apply when revived**: first decide whether the solution is an **Attribute**-level
`if:`, a generalized filter-like system, or something else. Don't just add the field without
a design discussion.

### Root-key auto-derivation from Descriptor#name

**Feature**: infer the **Root Key** string from `Descriptor#name` (e.g., `"PostSerializer"` →
`"post"` / `"posts"`) instead of requiring a per-call string.

**Why punted**: pluralization is fragile; callers who want auto-derivation build it at the
Panko-DSL layer where they own the naming conventions.

**How to apply when revived**: probably never — keep at the consumer layer.

### Hash-mode default key type — flip `Config#hash_output_key_type` to `:symbol`

**Feature**: change the default of `Config#hash_output_key_type` from `:string` to
`:symbol`. The flag and both emit paths already exist (see `config.rb:38`,
`generators/record_access/{generic,specialized}.rb`); only the default would move.

**Why punted**: v1 defaults to String keys to match Panko's `ObjectWriter`
(`Panko::Attribute` stores `name_str` and the writer assigns it as the Hash key).
Verified at runtime: Panko's `serialize` returns `{"name" => ...}`; Oj-Serializers'
`render_as_hash` returns `{name: ...}` (Symbol, via hash-literal codegen). A
micro-benchmark in `benchmarks/simple_hash_keys.rb` showed Symbol keys ~9–11% faster
on bare Hash construction (Symbol#hash is cached; String#hash recomputes each call),
but flipping the default is a behavior break for callers reading the Hash and no
consumer has asked. Wait for Panko (or another caller) to request it, or for
end-to-end benchmarks to show the gap dominates dispatch overhead.

**How to apply when revived**: change `Config::DEFAULTS[:hash_output_key_type]` to
`:symbol` and update `config_spec.rb` plus any Hash-mode snapshot fixtures. Decide
separately whether `hash_record_key_type` should follow (it's a different axis —
record-side lookup, not output shape). Coordinate the Panko-side expectation flip
in the same release.
