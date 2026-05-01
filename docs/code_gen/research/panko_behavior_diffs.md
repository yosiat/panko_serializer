# Panko vs scg `raw+val` — behavior differences

## Overview

This note is a verification log for [#60 (S12.5)](https://github.com/yosiat/serializers-code-gen/issues/60),
the slice introducing scg's `raw+val` JSON-mode emit path for AR `:json`
/ `:jsonb` columns. The `raw+val` path is designed for byte-parity with
`panko_serializer` 0.8.5 — it pushes AR's stored bytes verbatim through
`Oj::StringWriter#push_json`, the same C-call Panko uses. This doc
captures the small surface where parity is intentionally broken: a
handful of stress shapes where Panko's C extension raises and `raw+val`
falls through to `push_value(_read_attribute(...))` instead, plus the
shapes where `raw+val`'s byte stream diverges from today's
`push_value(Hash)` path because Panko's contract was (silently)
different from scg's all along. All snippets below were run against the
gem versions pinned in `phase_1_report.md § 2` (`panko_serializer 0.8.5`
on Ruby 4.0.2 + YJIT, AR 8.1, Oj 3.17, SQLite 2.9.3 with `t.json`); each
output line is verbatim stdout.

The reproducers boot AR + SQLite + a minimal `Post` model with `t.json
:metadata`, define a descriptor, compile the scg generated class, and
run all three paths (today's scg `push_value`, the proposed `raw+val`,
Panko 0.8.5) against the same records. Save each script under any name
and run it with `bundle exec ruby <name>.rb` from the repo root —
`bundler/setup` is implicit because every snippet starts with `require
"serializers_code_gen"` (the gem is on the load path inside its own
bundle). The `raw+val` helper is duplicated inline in each snippet so
each script stands alone; in production it lands in scg's codegen.

A note on Panko's exception classes: with `Oj.default_options[:mode] =
:rails` (the mode every Rails-shape host installs), Oj raises
`EncodingError` from the Ruby core, not `Oj::ParseError`. Panko's C
extension only rescues `Oj::ParseError` (`oj_parseerror_type`), so
`EncodingError` propagates unchanged. The `raw+val` validator rescues
both — the broader rescue is what makes the "scg degrades cleanly"
property hold under `:rails` mode.

## Stress cases — Panko crashes, scg `raw+val` degrades cleanly

Four database states make Panko 0.8.5 raise. In three of them
(malformed JSON, in-memory unsaved Hash, primitive non-string in DB),
`raw+val`'s `is_a?(String)` + `Oj.sc_parse` validator rejects the
input and routes through `push_value(_read_attribute("metadata"))` —
the slow path, but byte-identical to today's scg output. In the
fourth (primitive JSON string literal in DB), `raw+val` actually
takes the fast path because the raw bytes are still a String that
`Oj.sc_parse` accepts; only Panko crashes. Either way, the choice is
never "crash" vs "wrong bytes" — it's "crash" vs "the same bytes scg
has been emitting since S6".

### Malformed JSON in DB

A non-parseable byte sequence stored in the column. The most realistic
trigger is a manual `UPDATE` that bypasses AR's typecasting on write,
or a non-Rails writer that produces invalid JSON. AR's typecast on read
returns `nil` (the column type's `deserialize` rescues the parse error
internally). Panko reads `@value_before_type_cast`, hands it to
`Oj.sc_parse` inside `is_json_value`, the parse raises `EncodingError`
under `mode: :rails`, and the C extension's narrow `Oj::ParseError`
rescue lets it propagate. `raw+val` catches `EncodingError` in its own
validator and falls through to `push_value(nil)` → emits `null`.

```ruby
require "active_record"
require "sqlite3"
require "oj"

Oj.default_options = {mode: :rails, use_raw_json: true}

require "panko_serializer"
require "serializers_code_gen"

JSON_NOOP_PARSER = Object.new.freeze

def serialize_raw_val(records)
  writer = Oj::StringWriter.new(mode: :rails)
  writer.push_array
  records.each do |record|
    writer.push_object
    writer.push_value(record.id, "id")
    raw = record.read_attribute_before_type_cast("metadata")
    valid_string = raw.is_a?(String) && !raw.empty? && (begin
      Oj.sc_parse(JSON_NOOP_PARSER, raw, mode: :strict)
      true
    rescue Oj::ParseError, EncodingError
      false
    end)
    if valid_string
      writer.push_json(raw, "metadata")
    else
      writer.push_value(record._read_attribute("metadata"), "metadata")
    end
    writer.pop
  end
  writer.pop
  writer.to_s.chomp
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table :posts, force: true do |t|
    t.json :metadata
  end
end

class Post < ActiveRecord::Base
end

Post.insert_all([{metadata: {"ok" => true}}])
ActiveRecord::Base.connection.execute(
  "UPDATE posts SET metadata = '{not json' WHERE id = 1"
)

records = [Post.find(1)]

descriptor = SerializersCodeGen::Descriptor.new(
  name: "PostSerializer",
  models: [Post],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :metadata, source: :metadata)
  ],
  method_attributes: [],
  associations: []
)
scg_json = SerializersCodeGen.compile(descriptor, output: :json).new(descriptor: descriptor)

class PostPankoSerializer < Panko::Serializer
  attributes :id, :metadata
end

run = ->(label, &blk) {
  begin
    puts "#{label}: #{blk.call.inspect}"
  rescue => e
    puts "#{label}: RAISED #{e.class}: #{e.message}"
  end
}

run.call("scg/json (today)") { scg_json.serialize_many(records) }
run.call("scg/json/raw+val") { serialize_raw_val(records) }
run.call("panko/json")       { Panko::ArraySerializer.new(records, each_serializer: PostPankoSerializer).to_json }
```

Output (verbatim):

```
scg/json (today): "[{\"id\":1,\"metadata\":null}]"
scg/json/raw+val: "[{\"id\":1,\"metadata\":null}]"
panko/json: RAISED EncodingError: not a number or other value (after ) at line 1, column 1 [parse.c:637] in '{not json
```

### In-memory unsaved Hash assignment

A new (unsaved) record with `metadata` assigned directly: AR stores the
Hash as the typecast value, and `read_attribute_before_type_cast`
returns the same Hash (not a String). Panko reads `@value_before_type_cast`,
sees a non-String, and `is_json_value` returns the value itself
(non-`Qfalse`); the C path sets `isJson = Qtrue` and calls
`Oj::StringWriter#push_json(Hash, key)`, which raises `TypeError: no
implicit conversion of Hash into String`. `raw+val`'s `is_a?(String)`
guard short-circuits before any parse, falling through to
`push_value(record._read_attribute("metadata"))` and emitting the Hash
through `Oj`'s normal Hash encoder.

Replace the database setup (the `Post.insert_all` + `connection.execute`
block) in the snippet above with:

```ruby
post = Post.new(id: 1, metadata: {"a" => 1})
records = [post]
```

Output:

```
scg/json (today): "[{\"id\":1,\"metadata\":{\"a\":1}}]"
scg/json/raw+val: "[{\"id\":1,\"metadata\":{\"a\":1}}]"
panko/json: RAISED TypeError: no implicit conversion of Hash into String
```

### Primitive non-string in DB (SQLite stores it as Integer)

A bare JSON literal like `42` stored via raw `UPDATE`. SQLite's column
affinity coerces the literal — `'42'` becomes Integer 42 in
`read_attribute_before_type_cast` (not the String `"42"`). Panko
reads the Integer from `@value_before_type_cast`, `is_json_value`
returns the value (non-`Qfalse`, non-String) and `push_json(Integer,
key)` raises `TypeError: no implicit conversion of Integer into
String`. `raw+val`'s `is_a?(String)` guard rejects the Integer, falls
through, and `push_value(42)` writes the literal directly through
`Oj`. (On Postgres, AR keeps the raw bytes as a String even for
primitive literals; the `raw+val` path then validates with
`Oj.sc_parse` and emits the bytes verbatim. The two adapter shapes are
not byte-identical to each other, but neither raises.)

Replace the database stomp (`UPDATE posts SET metadata = '{not json'`)
in the malformed snippet with:

```ruby
ActiveRecord::Base.connection.execute(
  "UPDATE posts SET metadata = '42' WHERE id = 1"
)
```

Output:

```
scg/json (today): "[{\"id\":1,\"metadata\":42}]"
scg/json/raw+val: "[{\"id\":1,\"metadata\":42}]"
panko/json: RAISED TypeError: no implicit conversion of Integer into String
```

A primitive JSON **string** literal (`'"hello"'`) is stored by SQLite
as the String `"\"hello\""` (with the inner quotes preserved), so it
satisfies `raw+val`'s `is_a?(String)` check and `Oj.sc_parse` accepts
it as a valid JSON document. `raw+val` therefore takes the fast path
and emits `"hello"`. Panko hits the same shape but `Oj.sc_parse` under
`mode: :rails` raises `EncodingError: Empty input` after consuming the
top-level string — same root cause as the malformed case (Panko's
narrow rescue) — so this is also a "Panko crashes, raw+val degrades
cleanly" row.

```
scg/json (today): "[{\"id\":1,\"metadata\":\"hello\"}]"
scg/json/raw+val: "[{\"id\":1,\"metadata\":\"hello\"}]"
panko/json: RAISED EncodingError: Empty input (after ) at line 1, column 7 [parse.c:1239] in '"hello"
```

## Output bytes — `raw+val` matches Panko, differs from today's scg

For records whose stored bytes survived `Type::Json#serialize` on
write, `raw+val` re-emits those bytes verbatim through `push_json` —
which is exactly what Panko has always done. Today's scg path goes
through `Oj::StringWriter#push_value(Hash)` instead, which dispatches
to `Hash#as_json` and re-encodes from the typecast Ruby value. The
re-encoding is not lossless: AS's `encode_without_escape` (used by
`Type::Json#serialize` on **write**) doesn't HTML-escape `<`, `>`, `&`
or the JS-line-separator codepoints, but Oj in `:rails` mode escapes
them on **read** through `push_value`. Floats round-trip through
`Float#to_s` in `Oj`'s `:rails` mode, normalizing `-0.0` to `0.0` and
expanding scientific notation. `raw+val` skips the round-trip entirely
and ships the stored bytes — closing the gap with Panko at the cost of
deviating from the scg path callers have observed since S6.

The five rows below share one fixture pattern: pre-encode JSON in Ruby,
insert via raw SQL so the bytes hit the column unmodified, read back
through AR. Adapt the malformed snippet by replacing the
`Post.insert_all` + stomp pair with the per-row insert shown.

### HTML special characters (`</script>`)

`Type::Json#serialize` on write does not escape `<` / `>` / `&` —
that's an `encode_without_escape` choice, since the JSON spec doesn't
require it. `Hash#as_json` produces `"</script>"`; today's scg emit
goes through `push_value(Hash) → Hash#as_json → Oj write` and Oj in
`:rails` mode escapes the angle brackets to `\u003c` / `\u003e`.
`raw+val` and Panko emit the stored bytes (`</script>`) unchanged.

```ruby
raw_json = '{"html":"</script>"}'
ActiveRecord::Base.connection.execute(
  "INSERT INTO posts (id, metadata) VALUES (1, #{ActiveRecord::Base.connection.quote(raw_json)})"
)
records = [Post.find(1)]
```

| path             | output                                                                |
| ---------------- | --------------------------------------------------------------------- |
| scg/json (today) | `"[{\"id\":1,\"metadata\":{\"html\":\"\\u003c/script\\u003e\"}}]"`    |
| scg/json/raw+val | `"[{\"id\":1,\"metadata\":{\"html\":\"</script>\"}}]"`                |
| panko/json       | `"[{\"id\":1,\"metadata\":{\"html\":\"</script>\"}}]\n"`              |

The trailing `\n` on the Panko row is `Panko::ArraySerializer#to_json`'s
own formatting and is unrelated to the per-attribute bytes — every
Panko row in this section ends in `\n` for the same reason. (scg's
`writer.to_s.chomp` strips it; `raw+val` matches that contract.)

### U+2028 line separator

JavaScript pre-ES2019 treats U+2028 as a line terminator inside
strings, breaking embedded `<script>` payloads. AS's
`encode_without_escape` writes the codepoint raw. `push_value(Hash)`
under Oj `:rails` escapes it to ` `. `raw+val` and Panko emit the
raw codepoint. The output rows below use `<U+2028>` as a placeholder
for the literal codepoint (markdown can't render it visibly inside a
table cell).

```ruby
raw_json = "{\"sep\":\"a\u2028b\"}"
ActiveRecord::Base.connection.execute(
  "INSERT INTO posts (id, metadata) VALUES (1, #{ActiveRecord::Base.connection.quote(raw_json)})"
)
records = [Post.find(1)]
```

| path             | output                                                              |
| ---------------- | ------------------------------------------------------------------- |
| scg/json (today) | `"[{\"id\":1,\"metadata\":{\"sep\":\"a\u2028b\"}}]"`               |
| scg/json/raw+val | `"[{\"id\":1,\"metadata\":{\"sep\":\"a<U+2028>b\"}}]"`              |
| panko/json       | `"[{\"id\":1,\"metadata\":{\"sep\":\"a<U+2028>b\"}}]\n"`            |

### U+2029 paragraph separator

Same root cause as U+2028 — paired codepoint with the same JS-line-
terminator semantics, same write/read asymmetry. `<U+2029>` is the
placeholder convention from the previous section.

```ruby
raw_json = "{\"sep\":\"a\u2029b\"}"
ActiveRecord::Base.connection.execute(
  "INSERT INTO posts (id, metadata) VALUES (1, #{ActiveRecord::Base.connection.quote(raw_json)})"
)
records = [Post.find(1)]
```

| path             | output                                                              |
| ---------------- | ------------------------------------------------------------------- |
| scg/json (today) | `"[{\"id\":1,\"metadata\":{\"sep\":\"a\u2029b\"}}]"`              |
| scg/json/raw+val | `"[{\"id\":1,\"metadata\":{\"sep\":\"a<U+2029>b\"}}]"`              |
| panko/json       | `"[{\"id\":1,\"metadata\":{\"sep\":\"a<U+2029>b\"}}]\n"`            |

### Negative-zero float (`-0.0`)

`Float#to_s` returns `"-0.0"` for negative zero. AS's `encode_without_escape`
preserves it on write. Oj in `:rails` mode normalizes to `"0.0"` on
read through `push_value`, dropping the sign. `raw+val` and Panko emit
the stored `-0.0`.

```ruby
raw_json = '{"v":-0.0}'
ActiveRecord::Base.connection.execute(
  "INSERT INTO posts (id, metadata) VALUES (1, #{ActiveRecord::Base.connection.quote(raw_json)})"
)
records = [Post.find(1)]
```

| path             | output                                                |
| ---------------- | ----------------------------------------------------- |
| scg/json (today) | `"[{\"id\":1,\"metadata\":{\"v\":0.0}}]"`            |
| scg/json/raw+val | `"[{\"id\":1,\"metadata\":{\"v\":-0.0}}]"`           |
| panko/json       | `"[{\"id\":1,\"metadata\":{\"v\":-0.0}}]\n"`         |

### Scientific notation (`1e-300`, `1e300`)

AS writes scientific-notation floats as the shortest round-trip form
(`1e-300`, `1e300`). Oj in `:rails` mode prints them via
`Float#to_s`, which formats as `1.0e-300` and `1.0e+300` — extra
mantissa zero, explicit `+` on the positive exponent. `raw+val` and
Panko emit the stored compact form.

```ruby
[
  [1, '{"v":1e-300}'],
  [2, '{"v":1e300}']
].each do |id, raw_json|
  ActiveRecord::Base.connection.execute(
    "INSERT INTO posts (id, metadata) VALUES (#{id}, #{ActiveRecord::Base.connection.quote(raw_json)})"
  )
end
records = Post.order(:id).to_a
```

| path             | output                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------- |
| scg/json (today) | `"[{\"id\":1,\"metadata\":{\"v\":1.0e-300}},{\"id\":2,\"metadata\":{\"v\":1.0e+300}}]"`          |
| scg/json/raw+val | `"[{\"id\":1,\"metadata\":{\"v\":1e-300}},{\"id\":2,\"metadata\":{\"v\":1e300}}]"`               |
| panko/json       | `"[{\"id\":1,\"metadata\":{\"v\":1e-300}},{\"id\":2,\"metadata\":{\"v\":1e300}}]\n"`             |

## Inherited Panko behavior — in-place mutation goes stale

In-place mutation of the typecast Hash without a `save` (or
`metadata_will_change!`) is a shape `raw+val` inherits from Panko, not
introduced by scg. Both raw-passthrough emitters read
`@value_before_type_cast` (the original String, before AR built the
typecast Hash) and never observe the mutation; today's scg goes
through `_read_attribute → typecast Hash`, sees the mutation, and emits
the post-mutation bytes. The contract callers should use is the same
one Panko ships implicitly: reassign (`record.metadata =
record.metadata.merge(...)`) or dirty-flag (`record.metadata_will_change!`)
before serializing if you mutated in place. The dirty-tracking guard
considered for scg was rejected in `phase_1_report.md § 8.1` — it
costs ~13 allocs/record, turning the fix into a regression.

```ruby
Post.insert_all([{metadata: {"a" => 1}}])
post = Post.find(1)
post.metadata["new"] = "v"
records = [post]
```

| path             | output                                                            |
| ---------------- | ----------------------------------------------------------------- |
| scg/json (today) | `"[{\"id\":1,\"metadata\":{\"a\":1,\"new\":\"v\"}}]"`            |
| scg/json/raw+val | `"[{\"id\":1,\"metadata\":{\"a\":1}}]"`                          |
| panko/json       | `"[{\"id\":1,\"metadata\":{\"a\":1}}]\n"`                        |

Unlike the byte-divergence rows in the previous section (HTML escape,
U+2028 / U+2029, `-0.0`, scientific notation) — which differ because Oj's
`:rails` mode re-encodes the typecast Hash on read in a way that does
not round-trip the bytes AS wrote on `serialize` — the mutation case
diverges because the **input** to the two emit paths differs. Today's
scg sees the mutated Hash (via `_read_attribute`); `raw+val` and Panko
see the original stored String (via `read_attribute_before_type_cast`).
Adopting `raw+val` is a behavior change for callers who rely on
mid-request mutation visibility — the contract narrows to match
Panko's. No spec or fixture in the codebase exercises the
mutation-visible shape; the regression spec for #60 will pin this row
along with the byte-divergence rows above so a future revert (or
adapter-driven typecast change) is caught.
