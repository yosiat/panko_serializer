# frozen_string_literal: true

require_relative "benchmarking_support"
require_relative "app"
require_relative "setup"

class AuthorFastSerializer < Panko::Serializer
  attributes :id, :name
end

class PostFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :created_at
end

class PostFastWithJsonSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :created_at, :data
end

class PostFastWithMethodCallSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :method_call

  def method_call
    object.id * 2
  end
end

class PostWithHasOneFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id

  has_one :author, serializer: AuthorFastSerializer
end

class AuthorWithHasManyFastSerializer < Panko::Serializer
  attributes :id, :name

  has_many :posts, serializer: PostFastSerializer
end

def benchmark(prefix, serializer, options = {})
  data = Benchmark.data
  posts = data[:all]
  posts_50 = data[:small]

  merged_options = options.merge(each_serializer: serializer)

  Benchmark.run("Panko_ActiveRecord_#{prefix}_Posts_#{posts.count}") do
    Panko::ArraySerializer.new(posts, merged_options).to_json
  end

  data = Benchmark.data
  posts = data[:all]
  posts_50 = data[:small]

  Benchmark.run("Panko_ActiveRecord_#{prefix}_Posts_50") do
    Panko::ArraySerializer.new(posts_50, merged_options).to_json
  end
end

benchmark "Simple", PostFastSerializer
benchmark "SimpleWithJson", PostFastWithJsonSerializer
benchmark "HasOne", PostWithHasOneFastSerializer
benchmark "SimpleWithMethodCall", PostFastWithMethodCallSerializer
benchmark "Except", PostWithHasOneFastSerializer, except: [:title]
benchmark "Only", PostWithHasOneFastSerializer, only: [:id, :body, :author_id, :author]
