# Panko

[![Build Status](https://travis-ci.org/yosiat/panko_serializer.svg?branch=master)](https://travis-ci.org/yosiat/panko_serializer)

Panko is library which is inspired by ActiveModelSerializers 0.9 for serializing ActiveRecord objects to JSON strings, fast.

To achieve it's performance:

* Oj - Panko relies Oj since it's fast and allow to to serialize incrementally using `Oj::StringWriter`
* Serialization Descriptor - Panko computes most of the metadata ahead of time, to save time later in serialization.
* Type casting — Panko does type casting by it's self, instead of relying ActiveRecord.

To dig deeper about the performance choices, read [Design Choices](https://github.com/yosiat/panko_serializer/wiki/Design-Choices).

### Status

Panko is not ready for official release - it's missing documentation, tests which all be done incrementally.
If you want to start using Panko to see if it helps you, you are welcome! but check it well before deploying to Production.


## Installation

To install Panko, all you need is to add it to your Gemfile:

```ruby
gem "panko_serializer"
```

Then, install it on the command line:

```
> bundle install
```



## Usage

### Getting Started

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
   render json: Panko::ArraySerializer(users, each_serializer: UserSerializer).to_json
 end
end
```

And voila, we have endpoint which serialize users using Panko!


## Features

### Attributes

Attributes allow you to specify which record attributes you want to serialize,
There are two types of attributes:

* Field - simple columns defined on the record it self.
* Virtual/Method - this allows to include properties beyond simple fields.

Example:

```ruby
class UserSerializer < Panko::Serializer
 attributes :full_name
 
 def full_name
  "#{object.first_name} #{object.last_name}"
 end
end
```

As you can see, in order to access the serialized record, you need to access `object`.
If you want to pass data to the serializer, beyond the serialized record, you can pass `context` to the serializer (both in single and array serializer).

#### TODO:
Finished feature, will add documentation sson:
- Realtionships - `has_one`, `has_many`
- Filters & Nested Filters
- Reponse bag

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).


