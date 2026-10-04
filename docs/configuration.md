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
number `capacity + 1`, that class — and every later new class — is serialized
through the generic path instead, and Panko warns once per serializer class:

```
UserSerializer auto-specialization capacity (16) reached at AdminUser;
further record classes use the generic path. Raise
Panko::Config.auto_specialization.capacity if this is intentional.
```

The output is identical either way — the generic path produces the same bytes,
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

## When the settings apply

The `auto_specialization` settings are read when a serializer meets a record class for the first
time. Changing them later in the process doesn't recompile or discard variants
that already exist — which is why an initializer, before any serialization has
happened, is the right place to set them.
