# frozen_string_literal: true
require_relative "./benchmarking_support"
require_relative "./app"
require_relative "./setup"

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

def benchmark_ams(prefix, serializer, options = {})
  merged_options = options.merge(each_serializer: serializer)

  data = Benchmark.data
  posts = data[:all]
  posts_50 = data[:small]


  Benchmark.run("AMS_#{prefix}_Posts_#{posts.count}") do
    ActiveModel::ArraySerializer.new(posts, merged_options).serializable_object
  end

  data = Benchmark.data
  posts = data[:all]
  posts_50 = data[:small]

  Benchmark.run("AMS_#{prefix}_Posts_50") do
    ActiveModel::ArraySerializer.new(posts_50, merged_options).serializable_object
  end
end


benchmark_ams "HasOne", AmsPostWithHasOneFastSerializer
benchmark_ams "Simple", AmsPostFastSerializer
benchmark_ams "Except", AmsPostWithHasOneFastSerializer, except: [:title]
benchmark_ams "Include", AmsPostWithHasOneFastSerializer, include: [:id, :body, :author_id, :author]
