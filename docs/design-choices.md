---
title: Design Choices
layout: default
nav_order: 4
---

# Design Choices

In short, Panko is a serializer for ActiveRecord objects (it can't serialize any other object), which strives for high performance & simple API (which is inspired by ActiveModelSerializers).

Its performance is achieved by:

-   `Oj::StringWriter` - I will elaborate later.
-   Type casting — instead of relying on ActiveRecord to do its type cast, Panko is doing it by itself.
-   Figuring out the metadata, ahead of time — therefore, we ask less questions during the `serialization loop`.

## Serialization overview

First, let's start with an overview. Let's say we want to serialize an `User` object, which has
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
serializer = UserSerializer.new

# serialize to JSON
serializer.serialize_to_json(user)
```

Let's go over the steps that Panko will execute behind the scenes for this flow.
_I will skip the serializer definition part, because it's fairly simple and straightforward (see `lib/panko/serializer.rb`)._

First step, while initializing the UserSerializer, we will create a **Serialization Descriptor** for this class.
Serialization Descriptor's goal is to answer those questions:

-   Which fields do we have? In our case, `:age`, `:email`.
-   Which method fields do we have? In our case `:name`.
-   Which associations do we have (and their serialization descriptors)?

The serialization descriptor is a plain data container — it does not contain filtering logic. All `:only`/`:except` filtering is handled by `Panko::Filters`, a stateless filter engine that resolves options against the descriptor's attributes, method fields, and associations.

Now, that we have the serialization descriptor, the **Engine** (`Panko::Engine::Serializer`) takes over. It receives the `user` object and the serialization descriptor, and starts the serialization process which is separated to 3 parts:

-   Serializing Fields — looping through the descriptor's `fields`, reading them from the ActiveRecord object (see `Type Casting`), and writing them to the `Oj::StringWriter`.
-   Serializing Method Fields — setting the serializer's `@object` and `@context`, calling all the method fields and writing their return values to the writer.
-   Serializing Associations — repeating the process recursively for each `has_one`/`has_many` association.

The Engine contains multiple fast paths optimized for common cases:
-   **Ultra-fast path** — attributes only, no methods or associations. Pre-computes column index and writer caches for pure array access in the inner loop.
-   **Fast path** — attributes + a single `has_one` association. Inlines the association serialization to avoid method call overhead.
-   **Full path** — attributes + methods + associations. The general case.

For `serialize_many` (array serialization), the Engine inlines all work directly — it does not call `_serialize_one` per record — to maximize throughput.

Once this is finished, we have a nice JSON string.
Now let's dig deeper.

## Interesting parts

### Oj::StringWriter

If you read the code of ActiveRecord serialization code in Ruby, you will observe this flow:

1.  Get an array of ActiveRecord objects (`User.all` for example).
2.  Build a new array of hashes where each hash is an `User` with the attributes we selected.
3.  The JSON serializer, takes this array of hashes and loop them, and converts it to a JSON string.

This entire process is expensive in terms of Memory & CPU, and this where the combination of Panko and Oj::StringWriter really shines.

In Panko, the serialization process of the above is:

1.  Get an array of ActiveRecord objects (`User.all` for example).
2.  Create `Oj::StringWriter` and feed the values to it, via `push_value` / `push_object` / `push_object` and behind the scene, `Oj::StringWriter` will serialize the objects incrementally into a string.
3.  Get from `Oj::StringWriter` the completed JSON string — which is a no-op, since `Oj::StringWriter` already built the string.

### Figuring out the metadata, ahead of time.

Another observation I noticed in the Ruby serializers is that they ask and do a lot in a serialization loop:

-   Is this field a method? is it a property?
-   Which fields and associations do I need for the serializer to consider the `only` and `except` options?
-   What is the serializer of this has_one association?

Panko tries to ask the bare minimum in serialization by building `Serialization Descriptor` for each serialization and caching it.

The Serialization Descriptor will do the filtering of `only` and `except` and will check if a field is a method or not (therefore Panko doesn't have list of `attributes`).

### Type Casting

This is the final part, which helped yield most of the performance improvements.
In ActiveRecord, when we read the value of an attribute, it does type casting of the DB value to its real Ruby type.

For example, time strings are converted to Time objects, Strings are duplicated, and Integers are converted from their values to Number.

This type casting is really expensive, as it's responsible for most of the allocations in the serialization flow and most of them can be "relaxed".

If we think about it, we don't need to duplicate strings or convert time strings to time objects or even parse JSON strings for the JSON serialization process.

What Panko does is that if we have ActiveRecord type string, we won't duplicate it.
If we have an integer string value, we will convert it to an integer, and the same goes for other types.

Panko includes specialized value writers for each type — `StringWriter`, `IntegerWriter`, `FloatWriter`, `BooleanWriter`, `DateTimeWriter`, `JsonWriter`, and `SubtypeWriter`. Each writer knows how to read the raw database value and push it directly to `Oj::StringWriter`, bypassing ActiveRecord's type casting entirely. The writer for each attribute is resolved once on the first record and cached for all subsequent records in the batch.

#### Time type casting

The `DateTimeWriter` handles time type casting with a focus on zero allocations. The goal is to produce a UTC ISO8601 string for JSON output without creating intermediate `Time` objects.

The time type casting works as follows:

-   If it's a string that ends with `Z`, and the string matches the UTC ISO8601 regex, then we just return the string.
-   If it's a string in database timestamp format, we convert it to UTC ISO8601 using `bytesplice` directly on a reusable buffer — no intermediate string allocations.
-   If it's none of the above, we let ActiveRecord type casting do its magic.

### IndexedRow fast path

On Rails 7.2+, ActiveRecord uses `ActiveRecord::Result::IndexedRow` to store query results as arrays with a shared column-index map, rather than individual attribute hashes per record. Panko detects this and takes a fast path: it reads attribute values directly from the raw row array using pre-computed column indexes, achieving O(1) field access and avoiding the overhead of ActiveRecord's attribute hash lookup.

When serializing a batch of records from the same query, the column indexes are identical for every row. Panko uses object identity checks (`equal?`) to detect this and skips redundant setup work, making batch serialization especially fast.
