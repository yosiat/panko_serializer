# frozen_string_literal: true
exit unless ENV.fetch("RAILS_VERSION", "4.2").start_with? "5"

require_relative "./benchmarking_support"
require_relative "./app"
require_relative "./setup"
require 'fast_jsonapi'

class AuthorSerializer
  include FastJsonapi::ObjectSerializer
  attributes :id, :name
end


class PostFastSerializer
  include FastJsonapi::ObjectSerializer
  attributes :id, :body, :title, :author_id, :created_at
end

class PostWithHasOneFastSerializer
  include FastJsonapi::ObjectSerializer
  attributes :id, :body, :title, :author_id

  has_one :author
end

class AuthorWithHasManyFastSerializer
  include FastJsonapi::ObjectSerializer
  attributes :id, :name

  has_many :posts, serializer: :post_fast
end


def benchmark(prefix, serializer, options = {})
  data = Benchmark.data
  posts = data[:all]
  posts_50 = data[:small]

  merged_options = options.merge(each_serializer: serializer)

  Benchmark.run("FastJSONAPI_#{prefix}_Posts_#{posts.count}") do
    serializer.new(posts, merged_options).serialized_json
  end

  data = Benchmark.data
  posts = data[:all]
  posts_50 = data[:small]

  Benchmark.run("FastJSONAPI_#{prefix}_Posts_50") do
    serializer.new(posts_50, merged_options).serialized_json
  end
end

benchmark "Simple", PostFastSerializer
benchmark "HasOne", PostWithHasOneFastSerializer, include: [:author]
