# `Model.define_attribute_methods` safety research

## Summary verdict

**Safe to call defensively at Compile time.** Implementation is byte-identical across Rails
7.2, 8.0, and 8.1. Idempotent (short-circuits on `@attribute_methods_generated`),
thread-safe (`Monitor`-based lock with double-checked read), and recursively defines
attribute methods on the superclass chain first so STI subclasses are handled automatically.
No CHANGELOG churn, no open deprecation issues across our supported versions.

One honest caveat: it's marked `:nodoc:`. That's a soft "we may change this" signal, not
a hard deprecation — Panko and many other libraries already rely on sibling `:nodoc:`
methods like `_read_attribute`. The Rails-version adapter wraps the call so a future
signature change is a one-line fix in one place.

## Per-subquestion answers

### 1. Idempotency

Safe. Returns `false` on the second-and-subsequent call, `true` on the call that actually
did the work. From Rails 8.1.3 `activerecord/lib/active_record/attribute_methods.rb:104-125`
(identical in 7.2 and 8.0 stable branches):

```ruby
def define_attribute_methods # :nodoc:
  return false if @attribute_methods_generated
  GeneratedAttributeMethods::LOCK.synchronize do
    return false if @attribute_methods_generated
    # ... actually define ...
    @attribute_methods_generated = true
  end
  true
end
```

No observable side effects beyond the first call: no callbacks, no extra allocations of
note, no state churn.

### 2. API stability across 7.2 → 8.0 → 8.1

Verified by fetching `activerecord/lib/active_record/attribute_methods.rb` from the
`7-2-stable`, `8-0-stable`, and local 8.1.3 gem — the three method bodies
(`define_attribute_methods`, `attribute_methods_generated?`, `undefine_attribute_methods`)
are **byte-identical**. Lock is `GeneratedAttributeMethods::LOCK = Monitor.new` in all three.

Searched the 7.2 and 8.0 `CHANGELOG.md` for any mention of `define_attribute_methods`,
`attribute_methods_generated`, or `GeneratedAttributeMethods` → zero matches in either
changelog. No deprecation notices. No open Rails issues that affect us.

### 3. Thread safety

Safe. Uses `Monitor` (re-entrant mutex) with a double-checked read. Safe to call
concurrently from multiple threads at boot (e.g., multi-worker warmup) — the second
caller sees `@attribute_methods_generated == true` and returns immediately without
taking the lock a second time.

### 4. STI behavior

Recursively defines on the superclass first:
```ruby
superclass.define_attribute_methods unless base_class?
```
So `Child.define_attribute_methods` ensures `Parent` is done too. Sibling subclasses are
independent — defining on `Child1` does not define on `Child2`. For `models: [Child1, Child2]`
in the specialized path, the library must call it on each class in the set (cheap, idempotent).

### 5. Alternative: `attribute_methods_generated?`

Public-ish (same `:nodoc:` tier). Reliable across versions — a plain `@attribute_methods_generated`
reader. Can be used to skip the call if already done, but given `define_attribute_methods` is
already a no-op in that case, the check is redundant. Not worth an extra line.

### 6. Introspection after defining

After a successful `define_attribute_methods`, `Model.instance_method(:column_name)` is
defined for every column in `columns_hash` — the method bodies live on the
`GeneratedAttributeMethods` module included into the class. Edge cases:

- **Virtual attributes** (`attribute :foo, :integer`): included in `attribute_names` and
  generate readers through the same path.
- **Composite primary keys**: each component column gets its reader.
- **Abstract classes**: the method early-returns without defining (`unless abstract_class?`).
  Library should skip abstract classes — emit a compile error if one appears in `models:`.
- **Schema-less models** (`establish_connection` not called): `load_schema` will raise.
  Library should let this raise naturally — it's a user setup error.

### 7. Performance cost

Microseconds-to-low-milliseconds per model. Dominated by `load_schema` on the first
call for a given model (queries the DB for column metadata once, then cached). Called
once per compiled serializer, so per-**Descriptor**, not per-request. Negligible in
practice.

### 8. Known issues / footguns

None found in 7.2, 8.0, or 8.1 changelogs or recent issues searches. The method predates
the Rails 5.x era and has been stable.

Footgun worth noting but not Rails-specific: if the model's DB connection is unavailable
at **Compile** time (e.g., CI without a DB, test suite that lazy-starts), `load_schema`
inside `define_attribute_methods` will raise. Library's response: re-raise with a message
like `"SerializersCodeGen cannot introspect <Model>: its schema is not loadable (#{err})"`.

## Recommended usage pattern

```ruby
def introspect(model_class)
  model_class.define_attribute_methods
  # now safe to use Model.instance_method(:col), columns_hash, etc.
rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError => e
  raise SerializersCodeGen::CompileError,
        "Cannot introspect #{model_class.name}: #{e.class} — is the DB connection ready?"
end
```

- Call at **Compile** time, inside the **Generator**'s specialized-path introspection.
- No need to gate on `attribute_methods_generated?` — the method self-gates.
- Wrap in the per-Rails adapter (see
  [`docs/open-questions.md#rails--rails-support-matrix-structure`](../open-questions.md)).
  The wrapper body is one line today; if a future Rails ever renames or moves the method,
  only the adapter changes.

## Cons / honest downsides

1. **`:nodoc:` API.** Rails can change it. Mitigation: per-version adapter, single point of change.
2. **Requires a live DB connection.** `load_schema` talks to the DB. If users compile at
   boot before `establish_connection`, it raises. The raise is appropriate — better than
   silently generating wrong code — but users need the error message to guide them.
3. **Side-effect on the class.** We mutate the model class by defining methods on its
   `GeneratedAttributeMethods` module. In practice, AR does this itself on first use, so
   we're just forcing it earlier. But: if a user is doing something unusual (e.g.,
   inspecting a model *before* any record access to check "are methods defined yet?"),
   our compile pass will flip that state. Vanishingly unlikely to matter.
4. **Abstract classes can't be introspected.** If a user puts an abstract class in
   `models:`, we have to refuse it at **Compile** time. Trivial check:
   `raise if model.abstract_class?` before calling `define_attribute_methods`.

## Sources

- Local gem: `activerecord-8.1.3/lib/active_record/attribute_methods.rb:98-149`.
- Rails 8.0 stable branch: fetched from
  `https://raw.githubusercontent.com/rails/rails/8-0-stable/activerecord/lib/active_record/attribute_methods.rb`
  — lines 107-156 match 8.1.3 byte-for-byte.
- Rails 7.2 stable branch: fetched from
  `https://raw.githubusercontent.com/rails/rails/7-2-stable/activerecord/lib/active_record/attribute_methods.rb`
  — lines 98-156 match 8.1.3 byte-for-byte.
- 7.2 CHANGELOG, 8.0 CHANGELOG: zero mentions of the three relevant symbols.
