# Associations

A serializer can define it's own associations - both `has_many` and `has_one` to serializer under the context of the object.

For example:

```ruby
class PostSerializer < Panko::Serializer
  attributes :title, :body

  has_one :author, serializer: AuthorSerializer
  has_many :comments, each_serializer: CommentSerializer
end
```

# Associations with aliases

An association key name can be aliased with the `name` option.

For example:
the `actual_author` property will be converted to `alias_author`.
```ruby
class PostSerializer < Panko::Serializer
  attributes :title, :body

  has_one :actual_author, serializer: AuthorSerializer, name: :alias_author
  has_many :comments, each_serializer: CommentSerializer
end
```
### Inference

Panko can find the type of the serializer by looking at the realtionship name, so instead specifying
the serializer at the above example, we can -

```ruby
class PostSerializer < Panko::Serializer
  attributes :title, :body

  has_one :author
  has_many :comments
end
```

The logic of inferencing is -
- Take the name of the relationship (for example - `:author` / `:comments`) singularize and camelize it
- Look for const defined with the name aboe and "Serializer" suffix (by using `Object.const_get`)

> If Panko can't find the serializer it will throw an error on startup time, for example: `Can't find serializer for PostSerializer.author has_one relationship`

## Nested Filters

As talked before, Panko allows you to filter the attributes of a serializer.
But Panko let you take that step further, and filters the attributes of you associations so you can re-use your serializers in your application.

For example, let's say one portion of the application needs to serializer list of posts and serializer their - `title`, `body`, author's id and comments id.

We can declare tailored serializer for this, or we can re-use the above defined serializer - `PostSerializer` and use nested filters.

```ruby
posts = Post.all

Panko::ArraySerializer.new(posts, only: {
  instance: [:title, :body, :author, :comments],
  author: [:id],
  comments: [:id],
})
```

Let's disect `only` option we passed -
* `instance` - list of attributes (and associations) we want to serializer for current instance of the serializer, in this case - `PostSerializer`.
* `author`, `comments` - here we specify the list of attributes we want to serialize for each association.

It's important to note that Nested Filters, are recursive, in other words, we can filter the association's associations.

For example, `CommentSerializer` have has_one association `Author`, and for each `comments.author` we only it's name.

```ruby
posts = Post.all

Panko::ArraySerializer.new(posts, only: {
  instance: [:title, :body, :author, :comments],
  author: [:id],
  comments: {
    instance: [:id, :author],
    author: [:name]
  }
})
```

As you see now in `comments` the `instance` have differenet meaning, the `CommentSerializer`.
