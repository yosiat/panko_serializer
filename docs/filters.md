---
title: Filters
layout: default
nav_order: 4
parent: Reference
---

# Filters

Filters let you serialize a subset of a serializer's attributes and
associations. Narrowing the output reduces both the payload size and the work
Panko does, and it lets you reuse one serializer for several endpoints instead
of writing a tailored serializer for each.

There are two filters:

-   **`only`** — serialize **only** these attributes / associations.
-   **`except`** — serialize everything **except** these.

## `only` and `except`

Pass `only:` or `except:` when constructing a serializer:

```ruby
class UserSerializer < Panko::Serializer
  attributes :id, :name, :email
end

# => {"name" => "..."}
UserSerializer.new(only: [:name]).serialize(User.first)

# => {"id" => ..., "email" => "..."}
UserSerializer.new(except: [:name]).serialize(User.first)
```

The same options work on [`Panko::ArraySerializer`]({% link serializers.md %}#serializing-a-collection):

```ruby
Panko::ArraySerializer.new(User.all, each_serializer: UserSerializer, only: [:name])
```

## Filtering associations

An association is filtered by its **key in the serializer**, not by the
underlying method it reads.

If you declared the association with a `name:` alias, use the alias. For
example, given:

```ruby
has_many :state_transitions, name: :history
```

the key to use in a filter is `:state_transitions` — the declared name — not
`:history`:

```ruby
PostSerializer.new(except: [:state_transitions])
```

## Nested filters

To filter the attributes of associations too, pass a Hash instead of an array.
The Hash uses `instance` for the current serializer's own fields, and one key
per association for that association's fields.

Say you need posts with only their `title`, `body`, the author's `id`, and the
comments' `id`:

```ruby
posts = Post.all

Panko::ArraySerializer.new(posts, each_serializer: PostSerializer, only: {
  instance: [:title, :body, :author, :comments],
  author: [:id],
  comments: [:id]
})
```

Reading the `only` Hash:

-   **`instance`** — the attributes and associations to serialize for the
    current serializer (here, `PostSerializer`). Associations you want to keep
    (`:author`, `:comments`) must be listed here.
-   **`author`, `comments`** — the attributes to serialize for each association.

Nested filters are **recursive** — an association's Hash can itself contain an
`instance` key and further association keys. For example, if `CommentSerializer`
has a `has_one :author`, you can serialize only each comment author's `name`:

```ruby
Panko::ArraySerializer.new(posts, each_serializer: PostSerializer, only: {
  instance: [:title, :body, :author, :comments],
  author: [:id],
  comments: {
    instance: [:id, :author],
    author: [:name]
  }
})
```

Inside `comments`, `instance` now refers to `CommentSerializer`'s own fields.

## `filters_for`
{: #filters-for }

When the same filtering logic recurs across your controllers, move it into the
serializer as a `self.filters_for(context, scope)` class method. Panko calls it
automatically on every serialization — you never call it yourself.

```ruby
class UserSerializer < Panko::Serializer
  attributes :id, :name, :email

  def self.filters_for(context, scope)
    {only: [:name]}
  end
end

# => {"name" => "..."}
UserSerializer.new.serialize(User.first)
```

`filters_for` receives the [`context` and `scope`]({% link serializers.md %}#context-and-scope)
passed to the serializer, so filtering can depend on them — for example,
exposing more fields to an admin:

```ruby
class UserSerializer < Panko::Serializer
  attributes :id, :name, :email

  def self.filters_for(context, scope)
    if context[:user_role] == "admin"
      {only: [:id, :name, :email]}
    else
      {only: [:id, :name]}
    end
  end
end

UserSerializer.new(context: {user_role: "admin"}).serialize(User.first)
# => {"id" => ..., "name" => "...", "email" => "..."}
```

The result of `filters_for` is **combined per key** with any `only` / `except`
passed to the constructor: a `filters_for` returning `{except: [:address]}`
merges with a constructor `only: [:name]`, applying both.

> See the original discussion: [github.com/yosiat/panko_serializer/issues/16](https://github.com/yosiat/panko_serializer/issues/16)
