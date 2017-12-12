# Getting Started

## Installation

To install Panko, all you need is to add it to your Gemfile:

```ruby
gem "panko_serializer"
```

Then, install it on the command line:

```
> bundle install
```


## Creating your first serializer

Let's create serializer and use it inside Rails controller.

```ruby
class PostSerializer < Panko::Serializer
  attributes :title
end

class UserSerializer < Panko::Serializer
  attributes :id, :name, :age

  has_many :posts, serializer: PostSerializer
end
```

As you can see, defining serializers is simple and resembles ActiveModelSerializers 0.9,
To utilize the `UserSerializer` inside a Rails controller and serialize some users, all we need to do is:

```ruby
class UsersController < ApplicationController
 def index
   users = User.includes(:posts).all
   render json: Panko::ArraySerializer.new(users, each_serializer: UserSerializer).to_json
 end
end
```

And voila, we have endpoint which serialize users using Panko!

