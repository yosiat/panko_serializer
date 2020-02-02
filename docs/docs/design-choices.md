---
id: design-choices
title: Design Choices
sidebar_label: Design Choices
---

In short, Panko, is a serializer for ActiveRecord objects (it can't serialize any other object), which strives for high performance & simple API (which is inspired by ActiveModelSerializers).

Its performance is achieved by:

* `Oj::StringWriter` - I will elaborate later.
* Type casting — instead of relying on ActiveRecord to do its type cast, Panko is doing it by itself.
* Figuring out the metadata, ahead of time — therefore, we ask less questions during the `serialization loop`.


## Serialization overview

First, let's start with overview. Let's say we want to serialize `User` object, which has
`first_name`, `last_name`, `age`, and `email` properties.

The serializer definition will be something like this:

```ruby
class UserSerializer < Panko::Serializer
  attributes :name, :age, :email
  
  def name
    "#{object.first_name} #{object.last_name}"
  end
end
```

And the usage of this serializer will be:

```ruby
# fetch user from database
user = User.first

# create serializer, with empty options
serializer = UserSerilizer.new

# serialize to JSON
serializer.serialize_to_json(user)
```

Let's go over the steps that Panko will execute behind the scenes for this flow.
_I will skip the serializer definition part, because it's fairly simple and straightforward (see `lib/panko/serializer.rb`)_

First step, while initializing the UserSerializer, we will create a **Serialization Descriptor** for this class.
Serialization Descriptor's goal is to answer those questions:

* Which fields do we have? In our case, `:age`, `:email`
* Which method fields do we have? In our case `:name`
* Which associations do we have (and their serialization descriptors)

The serialization description is also responsible for filtering the attributes (`only` \ `except`).

Now, that we have the serialization descriptor, we are finished with the Ruby part of Panko, and all we did here is done in *initialization time* and now we move to C code.

In C land, we take the `user` object and the serialization descriptor, and start the serialization process which is separated to 4 parts:

* Serializing Fields - looping through serialization descriptor's `fields` and read them from the ActiveRecord object (see `Type Casting`) and write them to the writer.
* Serializing Method Fields - creating (a cached) serializer instance, setting its `@object` and `@context`, calling all the method fields and writing them to the writer.
* Serializing associations — this is simple, once we have fields + method fields, we just repeat the process.

Once this is finished, we have nice JSON string.
Now let's dig deeper.

## Interesting parts

### Oj::StringWriter

If you read the code of ActiveRecord serialization code in Ruby, you will observe this flow:

1. Get an array of ActiveRecord objects (`User.all` for example)
2. Build new array of hashes where each hash is `User` with the attributes we selected
3. The JSON serializer, takes this array of hashes and loop them, and converts it to JSON string

This entire process is expensive in terms of Memory & CPU, and this where the combination of Panko and Oj::StringWriter really shines. 

In Panko, the serialization process of the above is:

1. Get an array of ActiveRecord objects (`User.all` for example)
2. Create `Oj::StringWriter` and feed the values to it, via `push_value` / `push_object` / `push_object` and behind the scene, `Oj::StringWriter` will serialize the objects incrementally into a string.
3. Get from `Oj::StringWriter` the completed JSON string — which is a no-op, since `Oj::StringWriter` already built the string.

### Figuring out the metadata, ahead of time.

Another observation I noticed in the ruby serializers is that they ask and do a lot in a serialization loop: 

* Is this field a method? is it a property?
* Which fields and associations do I need for the serializer to consider the `only` and `except` options
* What is the serializer of this has_one association?

Panko tries to ask the bare minimum in serialization by building `Serialization Descriptor` for each serialization and caching it.

The Serialization Descriptor will do the filtering of `only` and `except` and will check if a field is a method or not (therefore Panko doesn't have list of `attributes`)


### Type Casting

This is the final part, which helped yield most of the performance improvements.
In ActiveRecord, when we read a value of attribute, it does type casting of the DB value to its real ruby type.

For example, time strings are converted to Time objects, Strings are duplicated, and Integers are converts from their values to Number.

This type casting is really expensive, as it's responsible for most of the allocations in the serialization flow and most of them can be "relaxed".

If we think about it, we don't need to duplicate strings or convert time strings to time objects or even parse JSON strings for the JSON serialization process.

What Panko does is that if we have ActiveRecord type string, we won't duplicate it.
If we have an integer string value, we will convert it to an integer, and the same goes for other types.

All of these conversions are done in C, which of course yields a big performance improvement.

#### Time type casting
While you read Panko source code, you will encounter the time type casting and immediately you will have a "WTF?" moment.

The idea behind the time type casting code relies on the end result of JSON type casting — what we need in order to serialize Time to JSON? UTC ISO8601 time format representation.

The time type casting works as follows:

* If it's a string that ends with `Z`, and the strings matches the UTC ISO8601 regex, then we just return the string.
* If it's a string and it doesn't follow the rules above, we check if it's a timestamp in database format and convert it via regex + string concat to UTC ISO8601 - Yes, there is huge assumption here, that the database returns UTC timestamps — this will be configureable (before Panko official release).
* If it's none of the above, I will let ActiveRecord type casting do it's magic.

