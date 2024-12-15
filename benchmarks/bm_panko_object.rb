# frozen_string_literal: true

require_relative "benchmarking_support"
require_relative "app"
require_relative "setup"

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

def benchmark(prefix, serializer, options = {})
  posts = Benchmark.data[:all]

  merged_options = options.merge(each_serializer: serializer)

  Benchmark.run("Panko_ActiveRecord_#{prefix}_Posts_#{posts.count}") do
    Panko::ArraySerializer.new(posts, merged_options).to_a
  end

  posts_50 = Benchmark.data[:small]

  Benchmark.run("Panko_ActiveRecord_#{prefix}_Posts_50") do
    Panko::ArraySerializer.new(posts_50, merged_options).to_a
  end
end

benchmark "Simple", PostFastSerializer
benchmark "HasOne", PostWithHasOneFastSerializer
benchmark "Except", PostWithHasOneFastSerializer, except: [:title]
benchmark "Only", PostWithHasOneFastSerializer, only: [:id, :body, :author_id, :author]
