---
title: Configuration
layout: default
nav_order: 6
parent: Reference
---

# Configuration

Panko works with zero configuration. Its one tunable area is
**auto-specialization** — the per-record-class compilation described in
[Design Choices]({% link design-choices.md %}#specializing-per-record-class).

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

## When the settings apply

Both settings are read when a serializer meets a record class for the first
time. Changing them later in the process doesn't recompile or discard variants
that already exist — which is why an initializer, before any serialization has
happened, is the right place to set them.
