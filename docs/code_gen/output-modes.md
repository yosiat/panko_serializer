# Output Modes

Two **Output Modes** are supported: `:json` and `:hash`. Each produces a different
**Generated Class** with different internal structure, selected at **Compile** time.

## `:json` — String via Oj::StringWriter

### Shape

```ruby
class PostSerializer_JSON
  POOL = SerializersCodeGen::WritersPool::ThreadLocal.new(:_scg_writer__PostSerializer_JSON)

  # Public
  def serialize_one(record, context: nil, filters: nil)
    writer = POOL.checkout
    begin
      _write_one(record, writer, context, filters)
      writer.to_s
    ensure
      POOL.checkin(writer)
    end
  end

  def serialize_many(records, context: nil, filters: nil)
    writer = POOL.checkout
    begin
      writer.push_array
      records.each { |r| _write_one(r, writer, context, filters) }
      writer.pop
      writer.to_s
    ensure
      POOL.checkin(writer)
    end
  end

  # Internal — invoked by this class and by parent Generated Classes (Composition)
  def _write_one(record, writer, context, filters)
    writer.push_object
    # ... emitted attribute / method_attribute / association writes ...
    writer.pop
  end
end
```

### Writer lifecycle

- Each **Generated Class** holds a class-level `POOL` constant pointing at a per-class
  `WritersPool` instance ([`lib/serializers_code_gen/writers_pool.rb`](../lib/serializers_code_gen/writers_pool.rb)).
  The pool is keyed off a unique Symbol — `:_scg_writer__<Name>_JSON` — so two **Generated
  Classes** never share a stack and one class's pool can't corrupt another.
- `serialize_one` / `serialize_many` call `POOL.checkout` at the top, thread the
  **Writer** through `_write_one` (and through **Composition** as an explicit positional
  argument), call `writer.to_s`, then call `POOL.checkin(writer)` from an `ensure` block —
  so an exception in the body still returns the **Writer** to the stack cleared.
- The pool's storage is **fiber-local**. The `WritersPool::ThreadLocal` backend uses
  `Thread.current[]`, which is fiber-local per MRI (`thread.c:3812`,
  `"Thread#[] and Thread#[]= are not thread-local but fiber-local"`). When
  `ActiveSupport::IsolatedExecutionState` is loaded (Rails 7.0+), the
  `WritersPool::IsolatedExecutionState` backend is selected instead, aligning the pool's
  locality with AR ConnectionPool's locality (per-thread under Puma, per-fiber under
  Falcon). Backend selection happens once at **Compile** via
  `defined?(ActiveSupport::IsolatedExecutionState)` and is baked into the emitted source
  as a literal class name — no per-call branching.
- The **Writer** is reset (via `Oj::StringWriter#reset`) on `checkin`, not on `checkout`.
  This means the pool's slot holds a clean, empty-buffered **Writer** between calls; the
  high-water mark of one call's buffer doesn't leak into an unrelated call's `to_s` if
  the latter happens to fault before writing.
- Reentrancy is handled by the LIFO stack itself, with no depth counter or in-use flag. A
  **Method Attribute** body that re-enters `serialize_one` — either on the same
  **Generated Class** (recursive shape) or on a different one (cross-class call) — finds
  its pool's stack empty at depth 2 and allocates a fresh **Writer**; the matching
  `checkin` returns it; subsequent calls at the same depth reuse without further
  allocation. Steady-state pool size equals the peak observed reentrancy depth on that
  fiber for that **Generated Class**.
- The pool is gated by [`Config#pool_writer`](config.md#pool_writer) (default `true`).
  Setting it to `false` emits the pre-pooling source verbatim — `writer =
  Oj::StringWriter.new(mode: :rails)` inline, no `POOL` constant, no `begin`/`ensure`
  wrap — for ABI-strict callers or emergency rollback.

### Output shape

- `serialize_one` → a JSON object: `{"id":1,"title":"..."}`.
- `serialize_many` → a JSON array: `[{...}, {...}]`.
- When `Config#supports_root_key: true` and `root_key:` is passed, the output is wrapped:
  `{"post":{...}}` / `{"posts":[...]}`.

### Null **Association** handling

When a `has_one` **Association**'s **Source** returns `nil`, **Generated Class** writes
`"key":null` by default (configurable via `Config#null_for_missing_has_one: false` to omit).

`has_many` **Associations** whose **Source** returns an empty collection emit `"key":[]`.
No config knob for this — empty arrays are natural JSON.

## `:hash` — Ruby Hash with string keys

### Shape

```ruby
def serialize_one(record, context: nil, filters: nil)
  _to_hash(record, context, filters)
end

def serialize_many(records, context: nil, filters: nil)
  records.map { |r| _to_hash(r, context, filters) }
end

def _to_hash(record, context, filters)
  result = {}
  # ... emitted attribute / method_attribute / association writes into result ...
  result
end
```

### Key format

- Default: **string keys** (`{"id" => 1, "title" => "..."}`). Matches JSON round-trip
  semantics, matches Panko's current Hash-mode convention, matches `as_json`.
- Controlled by `Config#hash_output_key_type` — `:string` (default) or `:symbol`. See
  [config.md](config.md). Applies uniformly to every **Field** (**Attributes**, **Method
  Attributes**, and **Associations**) at every nesting depth.
- String keys are frozen literals under the `frozen_string_literal: true` pragma — no
  per-call allocation. Symbol keys are always interned.

### Output shape

- `serialize_one` → one Hash.
- `serialize_many` → `Array<Hash>`.
- When `Config#supports_root_key: true` and `root_key:` is passed, wrapped:
  `{"post" => {...}}` / `{"posts" => [...]}`.

### Null **Association** handling

- `has_one` returning `nil`: writes `"key" => nil` by default (configurable).
- `has_many` returning empty: writes `"key" => []`.

## Composition across modes

A **Generated Class** in `:json` mode holds nested **Generated Class** instances that are
also in `:json` mode. Same for `:hash`. There is no cross-mode composition. If a consumer
wants both modes, they **Compile** both and hold them independently.

## Why two Generated Classes per Descriptor, not two methods on one class

- Every call site in `PostSerializer_JSON` dispatches to `CommentSerializer_JSON#_write_one`
  — single receiver class, single method, monomorphic. YJIT/ZJIT specialize hard.
- Each class carries only the code actually used — no dead method bodies.
- **Dump** output is focused: one file shows only the mode you care about.
- Lazy: a consumer that only serves JSON never **Compile**s the Hash variant.
