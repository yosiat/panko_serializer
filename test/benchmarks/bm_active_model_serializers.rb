require_relative './benchmarking_support'
require_relative './app'
require_relative './setup'

class AmsAuthorFastSerializer < ActiveModel::Serializer
  attributes :id, :name
end

class AmsPostFastSerializer < ActiveModel::Serializer
  attributes :id, :body, :title, :author_id
end

class AmsPostWithHasOneFastSerializer < ActiveModel::Serializer
  attributes :id, :body, :title, :author_id

  has_one :author, serializer: AmsAuthorFastSerializer
end

def benchmark_ams prefix, serializer
  posts = Post.all.to_a
  posts_50 = posts.first(50).to_a

  Benchmark.ams("AMS_#{prefix}_Posts_#{posts.count}") do
    ActiveModel::ArraySerializer.new(posts, each_serializer: serializer).serializable_object
  end

  Benchmark.ams("AMS_#{prefix}_Posts_50") do
    ActiveModel::ArraySerializer.new(posts_50, each_serializer: serializer).serializable_object
  end
end


benchmark_ams 'Simple', AmsPostFastSerializer
benchmark_ams 'HasOne', AmsPostWithHasOneFastSerializer
