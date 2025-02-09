---
id: getting-started
title: Getting Started
sidebar_label: Getting Started
---
## Installation

To install Panko, all you need is to add it to your Gemfile:

```ruby

gem "panko_serializer"

```

Then, install it on the command line:

```

 bundle install

```

## Creating your first serializer

Let's create a serializer and use it inside of a Rails controller:

```ruby
class PostSerializer < Panko::Serializer
  attributes :title
end

class UserSerializer < Panko::Serializer
  attributes :id, :name, :age

  has_many :posts, serializer: PostSerializer
end
```

### Serializing an object

And now serialize a single object:

```ruby

# Using Oj serializer
PostSerializer.new.serialize_to_json(Post.first)

# or, similar to #serializable_hash
PostSerializer.new.serialize(Post.first).to_json

```

### Using the serializers in a controller

As you can see, defining serializers is simple and resembles ActiveModelSerializers 0.9.
To utilize the `UserSerializer` inside a Rails controller and serialize some users, all we need to do is:

```ruby

class UsersController < ApplicationController
 def index
   users = User.includes(:posts).all
   render json: Panko::ArraySerializer.new(users, each_serializer: UserSerializer).to_json
 end
end

```

And voila, we have an endpoint which serializes users using Panko!
