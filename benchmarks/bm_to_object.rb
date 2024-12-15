# frozen_string_literal: true

require_relative "benchmarking_support"
require_relative "app"
require_relative "setup"

class PostWithAliasModel < ActiveRecord::Base
  self.table_name = "posts"

  alias_attribute :new_id, :id
  alias_attribute :new_body, :body
  alias_attribute :new_title, :title
  alias_attribute :new_author_id, :author_id
  alias_attribute :new_created_at, :created_at
end

class PostWithAliasFastSerializer < Panko::Serializer
  attributes :new_id, :new_body, :new_title, :new_author_id, :new_created_at
end

def benchmark_aliased(prefix, serializer, options = {})
  posts = PostWithAliasModel.all.to_a
  posts_50 = posts.first(50).to_a

  merged_options = options.merge(each_serializer: serializer)

  Benchmark.run("Panko_#{prefix}_PostWithAliasModels_#{posts.count}") do
    Panko::ArraySerializer.new(posts, merged_options).to_json
  end

  Benchmark.run("Panko_#{prefix}_Posts_50") do
    Panko::ArraySerializer.new(posts_50, merged_options).to_json
  end
end

class AuthorFastSerializer < Panko::Serializer
  attributes :id, :name
end

class PostFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :created_at
end

class PostFastWithMethodCallSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :created_at, :method_call

  def method_call
    object.id
  end
end

class PostWithHasOneFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :created_at

  has_one :author, serializer: AuthorFastSerializer
end

class AuthorWithHasManyFastSerializer < Panko::Serializer
  attributes :id, :name

  has_many :posts, serializer: PostFastSerializer
end

def benchmark(prefix, serializer, options = {})
  posts = Benchmark.data[:all]

  merged_options = options.merge(each_serializer: serializer)

  Benchmark.run("Panko_#{prefix}_Posts_#{posts.count}") do
    Panko::ArraySerializer.new(posts, merged_options).to_a
  end

  posts_50 = Benchmark.data[:small]

  Benchmark.run("Panko_#{prefix}_Posts_50") do
    Panko::ArraySerializer.new(posts_50, merged_options).to_a
  end
end

benchmark "Simple", PostFastSerializer
benchmark "HasOne", PostWithHasOneFastSerializer
