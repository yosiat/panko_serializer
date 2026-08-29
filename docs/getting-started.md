---
title: Getting Started
layout: default
nav_order: 2
---

# Getting Started

## Installation

Add Panko to your Gemfile:

```ruby
gem "panko_serializer"
```

Then install it:

```
bundle install
```

There's no native extension to build — Panko is pure Ruby.

## Creating your first serializer

A serializer is a subclass of `Panko::Serializer` that declares which
attributes and associations to emit:

```ruby
class PostSerializer < Panko::Serializer
  attributes :title
end

class UserSerializer < Panko::Serializer
  attributes :id, :name, :age

  has_many :posts, serializer: PostSerializer
end
```

## Serializing an object

Create the serializer, then pass the object to serialize:

```ruby
# => a JSON String
PostSerializer.new.serialize_to_json(Post.first)

# => a Ruby Hash with string keys
PostSerializer.new.serialize(Post.first)
```

Use `serialize_to_json` when you want JSON, and `serialize` when you want a Hash
(for example, to nest inside a larger structure).

## Serializing a collection

For arrays and ActiveRecord relations, use `Panko::ArraySerializer` with
`each_serializer:`:

```ruby
users = User.all

Panko::ArraySerializer.new(users, each_serializer: UserSerializer).to_json
```

## Using serializers in a controller

Putting it together in a Rails controller:

```ruby
class UsersController < ApplicationController
  def index
    users = User.includes(:posts).all
    render json: Panko::ArraySerializer.new(users, each_serializer: UserSerializer).to_json
  end
end
```

And that's a Panko-serialized endpoint.

> Preload associations you serialize (`User.includes(:posts)` above) so
> serialization doesn't trigger N+1 queries.

## Next steps

-   [Serializers]({% link serializers.md %}) — the full `Panko::Serializer` /
    `Panko::ArraySerializer` API, including `context` and `scope`.
-   [Attributes]({% link attributes.md %}) and
    [Associations]({% link associations.md %}) — the serializer DSL in depth.
-   [Filters]({% link filters.md %}) — serialize a subset of attributes.
-   [Response]({% link response-bag.md %}) — compose serialized output into a
    larger JSON response.
