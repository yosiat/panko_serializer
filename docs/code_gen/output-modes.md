# Output Modes

Two **Output Modes** are supported: `:json` and `:hash`. Each produces a different
**Generated Class** with different internal structure, selected at **Compile** time.

## `:json` — String via Oj::StringWriter

### Shape

```ruby
# Public
def serialize_one(record, context: nil, filters: nil)
  writer = Oj::StringWriter.new(mode: :rails)
  _write_one(record, writer, context, filters)
  writer.to_s
end

def serialize_many(records, context: nil, filters: nil)
  writer = Oj::StringWriter.new(mode: :rails)
  writer.push_array
  records.each { |r| _write_one(r, writer, context, filters) }
  writer.pop
  writer.to_s
end

# Internal — invoked by this class and by parent Generated Classes (Composition)
def _write_one(record, writer, context, filters)
  writer.push_object
  # ... emitted attribute / method_attribute / association writes ...
  writer.pop
end
```

### Writer lifecycle

- A fresh `Oj::StringWriter` is allocated at the top of each public `serialize_one` /
  `serialize_many` call.
- The **Writer** is threaded through **Composition** as an explicit positional argument to
  `_write_one` — never held as an ivar. This keeps the **Generated Class** stateless and
  thread-safe.
- **Writer** pooling is deferred until benchmarks motivate it. See [deferred.md](deferred.md).

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

- Default: **string keys** (`{"id" => 1, "title" => "..."}`).
- Rationale: matches JSON round-trip semantics, avoids symbol-GC concerns on user-controlled
  input, and matches Panko's current Hash-mode convention.
- Optional: symbol keys via a config flag (not yet confirmed — see [open-questions.md](open-questions.md)).
- Keys are frozen string literals in the **Generated** source (`frozen_string_literal: true`
  pragma), so there's no per-call allocation.

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
