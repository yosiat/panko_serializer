---
title: Response
layout: default
nav_order: 5
parent: Reference
---

# Response

Say you build a JSON payload around a Panko serialization result, like this:

```ruby
class PostsController < ApplicationController
  def index
   posts = Post.all
   render json: {
     success: true,
     total_count: posts.count,
     posts: Panko::ArraySerializer.new(posts, each_serializer: PostSerializer).to_json
   }
  end
end
```

The `posts` value above ends up as a JSON string inside a JSON string. This is where `Panko::Response` helps:

```ruby
class PostsController < ApplicationController
  def index
   posts = Post.all
   render json: Panko::Response.new(
     success: true,
     total_count: posts.count,
     posts: Panko::ArraySerializer.new(posts, each_serializer: PostSerializer)
   )
  end
end
```

`posts` is now embedded as JSON, not as a string.

`Panko::Response` writes the serializer output straight into its own JSON writer, so the body
is built once. Calling `.to_json` on the `ArraySerializer` first, and wrapping the String in
`Panko::JsonValue`, gives the same output but copies the body one extra time.

To serialize a single object, use `Panko::Response.create`, since `Panko::Serializer` doesn't take the object in its constructor:

```ruby
class PostsController < ApplicationController
  def show
    post = Post.find(params[:id])

    render(
      json: Panko::Response.create do |r|
        {
          success: true,
          post: r.serializer(post, PostSerializer)
        }
      end
    )
  end
end
```

Inside a `create` block you can also nest a collection with
`r.array_serializer(records, serializer, options)`:

```ruby
render(
  json: Panko::Response.create do |r|
    {
      success: true,
      posts: r.array_serializer(Post.all, PostSerializer)
    }
  end
)
```

## JsonValue

When you already hold a JSON string, for example serialized posts read from a cache, wrap it in `Panko::JsonValue` so it is embedded as is:

```ruby
class PostsController < ApplicationController
  def index
   posts = Cache.get("/posts")

   render json: Panko::Response.new(
     success: true,
     total_count: posts.count,
     posts: Panko::JsonValue.from(posts)
   )
  end
end
```
