---
title: Attributes
layout: default
nav_order: 2
parent: Reference
---

# Attributes

Attributes declare which values a serializer emits. There are two kinds:

-   **Field attributes** — columns read directly off the record.
-   **Method attributes** — values computed by a method on the serializer.

```ruby
class UserSerializer < Panko::Serializer
  attributes :full_name

  def full_name
    "#{object.first_name} #{object.last_name}"
  end
end
```

Panko decides which is which automatically: if you define a method whose name
matches a declared attribute, that attribute becomes a method attribute;
otherwise it's read as a column.

## Field attributes

Field attributes name columns on the record you want to serialize:

```ruby
class UserSerializer < Panko::Serializer
  attributes :id, :name, :email
end
```

## Method attributes

A method attribute is used when the value is derived rather than stored. Define
a method with the attribute's name; it can read the record being serialized
through `object`:

```ruby
class PostSerializer < Panko::Serializer
  attributes :author_name

  def author_name
    "#{object.author.first_name} #{object.author.last_name}"
  end
end
```

Method attributes can also read `context` and `scope` — two per-serialization
values you can pass in. For example, exposing feature flags supplied via
`context`:

```ruby
class UserSerializer < Panko::Serializer
  attributes :id, :email, :feature_flags

  def feature_flags
    context[:feature_flags]
  end
end

serializer = UserSerializer.new(context: {feature_flags: FeatureFlags.all})
serializer.serialize(User.first)
```

See [Serializers → context and scope]({% link serializers.md %}#context-and-scope)
for the full picture, and [Skipping a field]({% link serializers.md %}#skipping-a-field)
for how a method attribute can omit its key entirely.

## Aliases

To expose an attribute under a different key, reach for `aliases` rather than a
method attribute.

You *could* rename with a method attribute:

```ruby
class PostSerializer < Panko::Serializer
  attributes :published_at

  def published_at
    object.created_at
  end
end
```

But this turns a column read into a method attribute — an extra method call on
every record, and the value skips Panko's column handling (for example, datetime
formatting in Hash mode). `aliases` keeps the plain column path while changing
the output key:

```ruby
class PostSerializer < Panko::Serializer
  aliases created_at: :published_at
end
```

Here `created_at` is read as a regular column, but emitted as `published_at`.

## Filtering attributes

To serialize a subset of attributes — with `only` / `except`, nested filters,
or `filters_for` — see [Filters]({% link filters.md %}).
