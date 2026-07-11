---
title: Design Choices
layout: default
nav_order: 4
---

# Design Choices

Panko is a serializer for ActiveRecord objects (it can serialize plain Ruby
objects too, but its fast paths are built around ActiveRecord) that aims for
high performance behind a small, simple API.

Its speed comes from three ideas, each explained below:

-   **Code generation** — Panko compiles a specialized serializer, in plain
    Ruby, once per serializer class, so the per-record work is straight-line
    code instead of a metadata-driven loop.
-   **Incremental JSON** — JSON is built incrementally with `Oj::StringWriter`,
    without an intermediate Hash.
-   **Ahead-of-time metadata** — everything Panko can figure out about a
    serializer (which fields are columns, which are methods, which associations
    exist) is resolved when the class is first used, not inside the
    serialization loop.

> Panko used to ship a C extension. It no longer does — the engine is now
> **pure Ruby** that Panko generates and the Ruby VM (with YJIT) compiles.
> There is nothing to build when you install the gem.

## Serialization overview

Let's say we want to serialize a `User` object that has `first_name`,
`last_name`, `age`, and `email` columns.

The serializer looks like this:

```ruby
class UserSerializer < Panko::Serializer
  attributes :name, :age, :email

  def name
    "#{object.first_name} #{object.last_name}"
  end
end
```

And using it:

```ruby
user = User.first
UserSerializer.new.serialize_to_json(user)
```

Here is what Panko does behind the scenes.

**First use of the class.** The DSL (`attributes`, `has_one`, `has_many`, …)
is accumulated into an immutable description of the serializer's shape, which
answers questions like:

-   Which values are plain columns? Here, `age` and `email`.
-   Which values are methods? Here, `name` (because a method with that name is
    defined).
-   Which associations exist, and what is each one's shape?

From that description Panko **generates a specialized Ruby class** and compiles
it once. It caches the compiled class per serializer and per output mode
(`:json` vs `:hash`), so this cost is paid a single time, not per record.

**Each serialization.** The generated class walks the record and writes each
field directly — reading columns through ActiveRecord's own attribute readers,
invoking your method attributes, and recursing into associations. In `:json`
mode it writes straight into an `Oj::StringWriter`; in `:hash` mode it builds a
Hash with string keys.

The result is either a JSON string (`serialize_to_json`) or a Ruby Hash
(`serialize`).

## The interesting parts

### Code generation

Most Ruby serializers interpret their configuration on every record: for each
field they ask "is this a method or a column?", "is it filtered out?", "what
serializer handles this association?". Those questions have the same answers
for every record, but they get re-asked millions of times.

Panko answers them **once**, when it first sees a serializer class, and then
generates a small, purpose-built Ruby class that hard-codes the answers. There
are no per-field branches on the hot path — the generated code for
`UserSerializer` reads `age`, reads `email`, and calls `name`, in a straight
line.

Generating plain Ruby (rather than interpreting a data structure, or shipping
C) has two payoffs:

-   **The VM optimizes it.** The emitted methods are small and monomorphic and
    keep a stable object shape, which is exactly what YJIT specializes well.
-   **It stays debuggable.** It's Ruby you can read; backtraces point at real
    method calls, not at a generic interpreter frame.

You never see any of this. You keep writing ordinary Panko serializers; the
code generation is entirely internal.

### What the generated code looks like

To make this concrete, here is the code Panko generates for a small serializer:

```ruby
class PostSerializer < Panko::Serializer
  attributes :id, :title, :body
end
```

Panko compiles a subclass whose JSON writer is straight-line — it reads each
value off the record and pushes it into the writer, with one branch for
plain-Hash records versus objects:

```ruby
def _write_one(record, writer, context, scope, filters)
  if record.is_a?(Hash)
    writer.push_object
    writer.push_value(record["id"], "id")
    writer.push_value(record["title"], "title")
    writer.push_value(record["body"], "body")
    writer.pop
  else
    writer.push_object
    writer.push_value(record.id, "id")
    writer.push_value(record.title, "title")
    writer.push_value(record.body, "body")
    writer.pop
  end
end
```

There are no per-field lookups or conditionals on the hot path — the field
names are baked into the method, and each value is read with ActiveRecord's own
reader (`record.title`) and pushed as-is. You can inspect this for any
serializer with `Panko::CodeGen.dump`. (The real output also wraps each field
in an `only`/`except` filter check, elided here for readability.)

### Incremental JSON

A typical Ruby JSON pipeline does three passes:

1.  Get an array of records (`User.all`).
2.  Build an array of Hashes, one per record.
3.  Hand that array to a JSON encoder, which walks it and produces a string.

Steps 2 and 3 allocate a lot — a Hash and several intermediate objects per
record — and cost CPU to build and re-walk. Panko skips the intermediate Hash
entirely by using [Oj](https://github.com/ohler55/oj)'s `Oj::StringWriter`:

1.  Get an array of records (`User.all`).
2.  Push values into an `Oj::StringWriter` as they're read; it appends to the
    output string incrementally.
3.  Ask the writer for the finished string — which is essentially free, because
    it's already built.

For the `:hash` output mode there is no writer; Panko builds the Hash directly.

### Reading values

Panko reads each attribute with ActiveRecord's own reader — `record.title` for
an object, `record["title"]` for a plain Hash — and writes the value straight
out. It does **not** re-implement type casting: the value you'd get from
`record.title` is the value Panko serializes.

The one transform Panko applies is to datetimes, and only so the two output
modes agree on their shape:

-   In **`:json`** mode, values are pushed into `Oj::StringWriter` untouched;
    Oj formats a `Time` / `Date` / `TimeWithZone` to an ISO-8601 string as it
    writes.
-   In **`:hash`** mode there is no writer, so Panko formats those same datetime
    types to the equivalent ISO-8601 string itself; every other value passes
    through unchanged. This is what keeps `serialize` and `serialize_to_json`
    producing matching datetime strings.

### Compiling ahead of time, and reusing instances

Two smaller choices round out the performance story:

-   **Compile once, per class.** The generated class is built and cached the
    first time a serializer is used. Every later call reuses it, so the
    generation cost never appears in your request path after warm-up.
-   **Pooled instances.** Serializing checks a generated instance out of a
    small pool and returns it afterward (its per-record state is cleared on
    return), which avoids allocating a fresh object graph for every call.

Together these keep the steady-state cost of serializing a record close to the
irreducible work of reading its values and writing them out.
