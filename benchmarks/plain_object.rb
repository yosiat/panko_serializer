# frozen_string_literal: true

require_relative "support/datasets"

class PlainAuthorSerializer < Panko::Serializer
  attributes :id, :name
end

class PlainPostSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :created_at
end

class PlainPostWithMethodCallSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :method_call

  def method_call
    object.id * 2
  end
end

class PlainPostWithHasOneSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :created_at

  has_one :author, serializer: PlainAuthorSerializer
end

benchmark_with_records("Simple", type: :plain_posts) { |r| Panko::ArraySerializer.new(r, each_serializer: PlainPostSerializer).to_json }
benchmark_with_records("HasOne", type: :plain_posts) { |r| Panko::ArraySerializer.new(r, each_serializer: PlainPostWithHasOneSerializer).to_json }
benchmark_with_records("MethodCall", type: :plain_posts) { |r| Panko::ArraySerializer.new(r, each_serializer: PlainPostWithMethodCallSerializer).to_json }
benchmark_with_records("Except", type: :plain_posts) { |r| Panko::ArraySerializer.new(r, each_serializer: PlainPostWithHasOneSerializer, except: [:title]).to_json }
benchmark_with_records("Only", type: :plain_posts) { |r| Panko::ArraySerializer.new(r, each_serializer: PlainPostWithHasOneSerializer, only: [:id, :body, :author_id, :author]).to_json }
