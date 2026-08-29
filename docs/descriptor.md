---
title: Descriptor
layout: default
nav_order: 7
parent: Reference
---

# Descriptor

`Panko::Descriptor` is a **read-only view of a serializer's shape** — the
attributes, method attributes, and associations it will emit, including the
nested shape of every association. It exists for tooling built *around*
serializers: association preloaders that derive `includes` from what a
serializer emits, documentation generators, API linters.

It is the supported introspection surface. How Panko represents serializers
internally is private and changes between releases; code that reads a
serializer's shape should go through `Panko::Descriptor` and nothing else.

## Getting a descriptor

The class-level `descriptor` returns the serializer's **declared** shape:

```ruby
class PostSerializer < Panko::Serializer
  attributes :title, :body

  has_many :comments, serializer: CommentSerializer
end

PostSerializer.descriptor
```

The instance-level `descriptor` returns the **effective** shape for that
instance — it honors `only` / `except` passed to the constructor and the
serializer's [`filters_for`]({% link filters.md %}#filters-for), so it
describes exactly what that instance will serialize:

```ruby
PostSerializer.new(only: [:title]).descriptor

Panko::ArraySerializer.new(posts,
  each_serializer: PostSerializer,
  only: {instance: [:title, :comments], comments: [:body]}).descriptor
```

## What it exposes

| Reader              | Returns                                                          |
| ------------------- | ---------------------------------------------------------------- |
| `serializer`        | the `Panko::Serializer` subclass this descriptor describes       |
| `attributes`        | the field attributes                                             |
| `method_attributes` | the [method attributes]({% link attributes.md %})                |
| `associations`      | the `has_one` / `has_many` associations                          |

Every field has a `name` — its **output key** — and a `source` — what it
**reads**:

-   An **attribute**'s `source` is the column (or record method) it reads.
    `name` and `source` differ under
    [`aliases`]({% link attributes.md %}): `aliases title: :headline` yields
    `name: :headline, source: :title`.
-   A **method attribute**'s `source` is the serializer method that computes
    it.
-   An **association**'s `source` is the declared relation — the one to pass
    to ActiveRecord. Its `name` differs when the association was declared
    with a `name:` alias. Associations also expose `kind` (`:has_one` /
    `:has_many`) and `descriptor` — the nested descriptor of the associated
    serializer.

All names are Symbols. When you need a String, `Symbol#name` returns a frozen
one without allocating.

```ruby
descriptor = PostSerializer.descriptor

descriptor.serializer                    # => PostSerializer
descriptor.attributes.map(&:name)        # => [:title, :body]

comments = descriptor.associations.first
comments.kind                            # => :has_many
comments.source                          # => :comments
comments.descriptor.attributes.map(&:name)  # => CommentSerializer's attributes
```

## Filters are reflected

An instance's descriptor exposes exactly the fields that instance emits — the
same rules as [filters]({% link filters.md %}), including nested filters and
`filters_for`:

```ruby
serializer = PostSerializer.new(only: {instance: [:title, :comments], comments: [:body]})

descriptor = serializer.descriptor
descriptor.attributes.map(&:name)                          # => [:title]
descriptor.associations.first.descriptor.attributes.map(&:name)  # => [:body]
```

## Example: deriving preloads

The typical consumer walks the association tree to build an ActiveRecord
`includes` Hash, so serializing a collection never N+1s — and because the
descriptor honors filters, associations that a filter drops are not preloaded:

```ruby
def includes_for(descriptor)
  descriptor.associations.to_h do |association|
    [association.source, includes_for(association.descriptor)]
  end
end

serializer = Panko::ArraySerializer.new(posts, each_serializer: PostSerializer)
posts = Post.all.includes(includes_for(serializer.descriptor))
```

## Cost

Descriptors are built for introspection, not paid for by serialization:

-   The class-level descriptor is built **once per serializer class**, frozen,
    and cached — repeated reads return the same object and allocate nothing.
-   An unfiltered instance's `descriptor` **is** that cached object.
-   A filtered instance's `descriptor` is a thin lazy view: each level is
    resolved on first read and memoized, so only the levels you visit are ever
    computed.
-   The serialization hot path does not build, read, or touch descriptors —
    calling `descriptor` (or never calling it) has no effect on `serialize` /
    `serialize_to_json` performance.
