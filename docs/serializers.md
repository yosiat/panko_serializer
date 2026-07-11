---
title: Serializers
layout: default
nav_order: 1
parent: Reference
---

# Serializers

Every serializer is a subclass of `Panko::Serializer`. It declares the shape of
the output with a small DSL, and is used to serialize either a single object or,
through `Panko::ArraySerializer`, a collection.

```ruby
class UserSerializer < Panko::Serializer
  attributes :id, :name, :email

  has_many :posts, serializer: PostSerializer
end
```

## Defining a serializer

The class-level DSL is covered in detail on its own pages:

-   [Attributes]({% link attributes.md %}) — `attributes`, method attributes, and `aliases`.
-   [Associations]({% link associations.md %}) — `has_one` and `has_many`.
-   [Filters]({% link filters.md %}) — `only` / `except` and `filters_for`.

## Serializing a single object

`Panko::Serializer` does **not** take the object in its constructor. You create
the serializer (optionally with options), then pass the object to a serialize
method:

```ruby
serializer = UserSerializer.new

# => a Ruby Hash with string keys
serializer.serialize(User.first)
# {"id" => 1, "name" => "Kim", "email" => "kim@example.com", "posts" => [...]}

# => a JSON String
serializer.serialize_to_json(User.first)
# "{\"id\":1,\"name\":\"Kim\",\"email\":\"kim@example.com\",\"posts\":[...]}"
```

| Method | Returns |
| --- | --- |
| `#serialize(object)` | a `Hash` with **string** keys |
| `#serialize_to_json(object)` | a JSON `String` |

A serializer instance is reusable — you can call `serialize` / `serialize_to_json`
on it more than once, with different objects.

## Serializing a collection

Use `Panko::ArraySerializer` for arrays and ActiveRecord relations. Unlike
`Panko::Serializer`, it **does** take the subjects in its constructor, along
with a required `each_serializer:`:

```ruby
users = User.all

array = Panko::ArraySerializer.new(users, each_serializer: UserSerializer)

array.to_json   # => a JSON String
array.to_a      # => an Array of Hashes
```

`ArraySerializer` accepts the same options as `Panko::Serializer` (below), plus
the required `each_serializer:`.

| Method | Returns |
| --- | --- |
| `#to_json` / `#serialize_to_json(subjects)` | a JSON `String` |
| `#to_a` / `#serialize(subjects)` | an `Array` of `Hash`es |

## Constructor options

Both `Panko::Serializer.new` and `Panko::ArraySerializer.new` accept the same
options.

| Option | Purpose |
| --- | --- |
| `context:` | An arbitrary bag of data available to method attributes — see below. |
| `scope:` | A per-serialization value (often the current user) available to method attributes and to `filters_for` — see below. |
| `only:` | Serialize **only** these attributes / associations. See [Filters]({% link filters.md %}). |
| `except:` | Serialize everything **except** these. See [Filters]({% link filters.md %}). |

```ruby
UserSerializer.new(
  context: {feature_flags: current_flags},
  scope: current_user,
  only: [:id, :name]
)
```

## `context` and `scope`

Method attributes run in the context of the serializer instance, so they can
read three accessors: `object`, `context`, and `scope`.

-   **`object`** — the record currently being serialized.
-   **`context`** — whatever you passed as `context:`. Use it for general data a
    serializer needs but that isn't on the record (feature flags, request data,
    a preloaded lookup table, …).
-   **`scope`** — whatever you passed as `scope:`. A per-serialization value —
    typically the current user or an authorization context — that your method
    attributes and `filters_for` can read.

Both default to `nil` when not provided, and both **propagate to nested
associations**: a `has_one` / `has_many` serializer sees the same `context` and
`scope` as its parent.

```ruby
class UserSerializer < Panko::Serializer
  attributes :id, :name, :can_edit

  def can_edit
    # `scope` here is whatever was passed as scope: — e.g. the current user
    object.editable_by?(scope)
  end
end

UserSerializer.new(scope: current_user).serialize(user)
```

```ruby
class PostSerializer < Panko::Serializer
  attributes :id, :title, :draft_banner

  def draft_banner
    context[:show_drafts] ? "DRAFT" : nil
  end
end

PostSerializer.new(context: {show_drafts: true}).serialize(post)
```

`scope` is also passed to `filters_for(context, scope)`, which lets you vary
which attributes are serialized based on it (for example, exposing more fields
to an admin). See [Filters]({% link filters.md %}#filters-for).

## Skipping a field

A method attribute can omit its key entirely by returning the `SKIP` sentinel.
This is different from returning `nil` (which emits `"key": null`) — `SKIP`
removes the key from the output altogether.

```ruby
class UserSerializer < Panko::Serializer
  attributes :id, :nickname

  def nickname
    object.nickname || SKIP
  end
end

# user with a nickname:    {"id" => 1, "nickname" => "Kat"}
# user without a nickname: {"id" => 2}
```

`SKIP` is available as a bare constant inside any `Panko::Serializer` subclass
(it is `Panko::Serializer::SKIP`).

### `SKIP` vs. filters

Both `SKIP` and filters drop fields, but they answer different questions:

-   **Filters (`only` / `except`)** drop fields **statically** — the set is
    fixed when you build the serializer. Reach for them when the caller knows up
    front which fields it wants. See [Filters]({% link filters.md %}).
-   **`SKIP`** drops a field **dynamically** — the decision is made per record,
    inside a method attribute, based on that record's own data (as in
    `object.nickname || SKIP` above).
