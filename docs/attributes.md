# Attributes

Attributes allow you to specify which record attributes you want to serialize,
There are two types of attributes:

* Field - simple columns defined on the record it self.
* Virtual/Method - this allows to include properties beyond simple fields.


```ruby
class UserSerializer < Panko::Serializer
 attributes :full_name
 
 def full_name
  "#{object.first_name} #{object.last_name}"
 end
end
```

## Field Attributes

Using field attributes you can control which columns of the given ActiveRecord object you want to serialize.

Instead of relying ActiveRecord to do it's type casting, Panko does on it's own for performance reasons (read more in [Design Choices](design-choices.md#type-casting)).


## Method Attributes

Method attributes are used when your serialized values can be derived from the object you are serializing.

The serializer's attribute methods can access the object being serialized as `object` -

```ruby
class PostSerializer < Panko::Serializer
 def author_name
  "#{object.author.first_name} #{object.author.last_name}"
 end
end
```

Another useful, thing you can pass your serializer is `context`, a `context` is a bag of data whom your serializer may need.

For example, here we will pass the current user:
```ruby
class UserSerializer < Panko::Serializer
  attributes :id, :email

  def feature_flags
    context[:feature_flags]
  end
end

serializer = UserSerializer.new(context: {
  feature_flags: FeatureFlags.all
})

serializer.serialize(User.first)
```

## Filters

Filters allows us to reduce the amount of attributes we can serialize, therefore reduce the data usage & performance of serializing.

There are two types of filters:
  * only - use those attributes **only** and nothing else
  * except - all attributes **except** those attributes

Usage example:
```ruby
class UserSerializer < Panko::Serializer
  attributes :id, :name, :email
end

# this line will return { 'name': '..' }
UserSerializer.new(only: [:name]).serialize(User.first)

# this line will return { 'id': '..', 'email': ... }
UserSerializer.new(except: [:name]).serialize(User.first)
```

## Aliases

Let's say we have attribute name that we want to expose to client as different name, the current way of doing so is using method attribute, for example:

```ruby
class PostSerializer < Panko::Serializer
  attributes :published_at

  def published_at
    object.created_at
  end
end
```

The downside of this approach is that `created_at` skips Panko's type casting, therefore we get direct hit on performance.

To fix this, we can use aliases -

```ruby
class PostSerializer < Panko::Serializer
  aliases created_at: :published_at
end
```

