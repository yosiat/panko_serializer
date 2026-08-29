---
title: Associations
layout: default
nav_order: 3
parent: Reference
---

# Associations

A serializer can nest other serializers through `has_one` and `has_many`, each
serializing a related object under the current one:

```ruby
class PostSerializer < Panko::Serializer
  attributes :title, :body

  has_one :author, serializer: AuthorSerializer
  has_many :comments, each_serializer: CommentSerializer
end
```

Use `serializer:` for `has_one` and `each_serializer:` for `has_many`.

## Aliasing an association

An association's output key can be renamed with the `name:` option. Here the
`actual_author` relation is emitted as `author`:

```ruby
class PostSerializer < Panko::Serializer
  attributes :title, :body

  has_one :actual_author, serializer: AuthorSerializer, name: :author
  has_many :comments, each_serializer: CommentSerializer
end
```

> When filtering, refer to an aliased association by its declared name (the
> first argument), not the `name:` alias. See [Filters]({% link filters.md %}#filtering-associations).

## Serializer inference

If you omit `serializer:` / `each_serializer:`, Panko infers it from the
association name:

```ruby
class PostSerializer < Panko::Serializer
  attributes :title, :body

  has_one :author      # => AuthorSerializer
  has_many :comments   # => CommentSerializer
end
```

The inference rule:

-   Take the association name (`:author`, `:comments`), singularize and
    camelize it.
-   Look for a constant with that name plus a `Serializer` suffix
    (`AuthorSerializer`, `CommentSerializer`).

> If Panko can't find a matching serializer, it raises at load time, e.g.
> `Can't find serializer for PostSerializer.author has_one relationship.`

## Filtering associations

Associations can be filtered — and their own attributes narrowed — with nested
filters. See [Filters → Nested filters]({% link filters.md %}#nested-filters).
