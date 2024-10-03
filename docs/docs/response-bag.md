---
id: response-bag
title: Response
sidebar_label: Response
---
Let's say you have some JSON payload which can is constructed using Panko serialization result,
like this:

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

The output of the above will be json string (for `posts`) inside json string and this were `Panko::Response` shines.

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

And everything will work as expected!

For a single object serialization, we need to use a different API (since `Panko::Serializer` don't accept an object in it's constructor):

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

## JsonValue

Let's take the above example further, we serialized the posts and cached it as JSON string in our Cache.
Now, you can wrap the cached value with `Panko::JsonValue`, like here -

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
