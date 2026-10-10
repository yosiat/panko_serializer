---
title: Configuration
layout: default
nav_order: 6
parent: Reference
---

# Configuration

Panko works with zero configuration. Two areas are tunable:
**auto-specialization**, the per-record-class compilation described in
[Design Choices]({% link design-choices.md %}#specializing-per-record-class),
and the size limit of the reused JSON writers (`writer_pool_max_bytes`).

Settings are process-global and read at serialization time. Set them once, in
an initializer, before your app starts serializing:

```ruby
# config/initializers/panko.rb
Panko.configure do |config|
  config.auto_specialization.capacity = 32
end
```

`Panko.configure` yields `Panko::Config`, so the block form above and direct
assignment are equivalent:

```ruby
Panko::Config.auto_specialization.capacity = 32
```

## `auto_specialization`

When a serializer first sees a given ActiveRecord class, Panko compiles a
variant of its generated code specialized for that model. Two settings control
this:

| Setting | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Whether specialized variants are compiled at all. `false` routes every record class to the generic code path. |
| `capacity` | `16` | Maximum specialized variants kept per serializer class and output mode. Record classes seen past the cap use the generic path. |

Assigning an invalid value raises `ArgumentError` immediately: `enabled` must
be exactly `true` or `false`, and `capacity` a positive `Integer`.

### `capacity`

Each serializer keeps at most `capacity` specialized variants **per output
mode** (JSON and Hash count separately). When a serializer meets record class
number `capacity + 1`, that class - and every later new class - is serialized
through the generic path instead, and Panko warns once per serializer class:

```
UserSerializer auto-specialization capacity (16) reached at AdminUser;
further record classes use the generic path. Raise
Panko::Config.auto_specialization.capacity if this is intentional.
```

The output is identical either way - the generic path produces the same bytes,
it just isn't specialized. Raise `capacity` when one serializer legitimately
serializes many record classes (a wide STI hierarchy, one serializer reused
across many models) and you see the warning.

### `enabled`

Setting `enabled = false` skips specialization entirely; every record class
uses the generic path. Useful when debugging or benchmarking, to rule
specialization in or out.

## `writer_pool_max_bytes`

`serialize_to_json` writes into an `Oj::StringWriter` and reuses it on the next
call on the same thread, which avoids allocating a writer per call. A writer
keeps the buffer it grew to, so after a call whose JSON is larger than
`writer_pool_max_bytes` the writer is dropped instead of reused, and the
garbage collector frees its buffer.

| Setting | Default | Meaning |
| --- | --- | --- |
| `writer_pool_max_bytes` | `1_048_576` (1 MB) | Largest JSON output whose writer is kept for reuse. |

Each thread keeps one writer (more only when a serializer calls
`serialize_to_json` from inside another serialization), and a kept writer holds
less than twice this limit. Lower it to cap per-thread memory further; outputs
above the limit pay one writer allocation per call. It must be a positive
`Integer`, and it is read on every call, so a change applies right away.

```ruby
Panko::Config.writer_pool_max_bytes = 256 * 1024
```

## Compiling at boot

Panko compiles a serializer the first time it is used. In a server that forks
workers (Puma or Unicorn with `preload_app`), every worker repeats that work
on its first requests. `Panko.compile_all` does it once, in the parent process,
so forked workers inherit the compiled code.

Declare the record classes each serializer serializes with `models`:

```ruby
class PostSerializer < Panko::Serializer
  models Post, Article
  attributes :id, :title
end
```

`models` is a hint: a record of any other class still serializes, and gets
its specialized variant on first use. Subclasses inherit the list, and calling
`models` again replaces it.

`models` also tells Panko what a child holds when its source is a plain method
rather than an association. Panko learns a child's class from the parent's
association reflection; a method has none, so without `models` the child
compiles on the generic path:

```ruby
class Post < ApplicationRecord
  has_many :comments
  has_many :notes

  def visible_comments = comments.reject(&:hidden)
  def attachments = comments.to_a + notes.to_a
end

class CommentSerializer < Panko::Serializer
  models Comment
  attributes :id, :body, :metadata
end

class AttachmentSerializer < Panko::Serializer
  models Comment, Note
  attributes :id, :metadata
end

class PostSerializer < Panko::Serializer
  has_many :visible_comments, serializer: CommentSerializer   # specialized for Comment
  has_many :attachments, serializer: AttachmentSerializer     # one body per model
end
```

- One declared model: the child compiles for that class, the same as an
  association child.
- Several: the child gets one body per model, picked per record by its exact
  class. Any other record gets the generic body.
- A reflection wins over `models` when the source is an association.
- A declared model that lacks one of the serializer's fields is skipped; its
  records get the generic body.

The specialized body writes `json` and `jsonb` columns as their stored text and
reads columns without the generic path's per-record method calls.

Call `compile_all` after the app is eager loaded and before workers fork:

```ruby
# config/initializers/panko.rb
Rails.application.config.after_initialize do
  Panko.compile_all if Rails.application.config.eager_load
end
```

It compiles every loaded `Panko::Serializer` subclass that declares a field,
for both output modes (`modes: [:json]` limits it to one). It returns a
`Panko::CompileAllResult`, where each serializer appears in exactly one field:

| Field | Holds |
| --- | --- |
| `compiled` | serializers compiled for every declared model |
| `without_models` | serializers with no `models`: the generic code is compiled, specialization happens on first use |
| `not_specialized` | serializer to the declared models that could not be specialized (not an ActiveRecord class, or specialization disabled) |
| `errors` | serializer to the error its compile raised |

To require `models` everywhere, assert on the result in a test:

```ruby
result = Panko.compile_all
expect(result.without_models).to be_empty
expect(result.not_specialized).to be_empty
expect(result.errors).to be_empty
```

If you warm serializers up before forking, do it after `compile_all`.

## When the settings apply

The `auto_specialization` settings are read when a serializer meets a record class for the first
time. Changing them later in the process doesn't recompile or discard variants
that already exist - which is why an initializer, before any serialization has
happened, is the right place to set them.
