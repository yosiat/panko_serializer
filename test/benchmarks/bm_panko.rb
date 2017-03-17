require_relative './benchmarking_support'
require_relative './app'
require_relative './setup'

class AuthorFastSerializer < Panko::Serializer
  attributes :id, :name
end


class PostFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id
end

class PostWithHasOneFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id

  has_one :author, serializer: AuthorFastSerializer
end

class AuthorWithHasManyFastSerializer < Panko::Serializer
  attributes :id, :name

  has_many :posts, serializer: PostFastSerializer
end


def benchmark prefix, serializer
  posts = Post.all.to_a
  posts_50 = posts.first(50).to_a


  Benchmark.ams("Panko_#{prefix}_Posts_#{posts.count}") do
   Panko::ArraySerializer.new(posts, each_serializer: serializer).serializable_object
  end

  Benchmark.ams("Panko_#{prefix}_Posts_50") do
   Panko::ArraySerializer.new(posts_50, each_serializer: serializer).serializable_object
  end

  posts_array_serializer = Panko::ArraySerializer.new(posts, each_serializer: serializer)

  Benchmark.ams("Panko_Reused_#{prefix}_Posts_#{posts.count}") do
    posts_array_serializer.subjects = posts
    posts_array_serializer.serializable_object
  end

  Benchmark.ams("Panko_Reused_#{prefix}_Posts_50") do
    posts_array_serializer.subjects = posts_50
    posts_array_serializer.serializable_object
  end
end

benchmark 'HasOne', PostWithHasOneFastSerializer
benchmark 'Simple', PostFastSerializer
