# frozen_string_literal: true

require_relative "support/benchmark"

# Panko::Response around serializer output, against the serializer's own to_json as the
# floor. The malloc column shows how many copies of the body a row keeps alive.

class ResponseAuthorPankoSerializer < Panko::Serializer
  attributes :id, :name, :email
end

class ResponseCommentPankoSerializer < Panko::Serializer
  attributes :id, :body
end

class ResponsePostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
  has_one :author, serializer: ResponseAuthorPankoSerializer
  has_many :comments, serializer: ResponseCommentPankoSerializer
end

benchmark_scenario "Response", type: :posts do |records|
  {
    "array_serializer/to_json" => -> {
      Panko::ArraySerializer.new(records, each_serializer: ResponsePostPankoSerializer).to_json
    },
    "response/array_serializer" => -> {
      Panko::Response.new(
        success: true,
        posts: Panko::ArraySerializer.new(records, each_serializer: ResponsePostPankoSerializer)
      ).to_json
    },
    "response/nested_response" => -> {
      Panko::Response.new(
        data: Panko::Response.new(
          posts: Panko::ArraySerializer.new(records, each_serializer: ResponsePostPankoSerializer)
        )
      ).to_json
    },
    "response/serializer_per_record" => -> {
      Panko::Response.create do |r|
        {posts: records.map { |post| r.serializer(post, ResponsePostPankoSerializer) }}
      end.to_json
    }
  }
end

class ResponseWidePostPankoSerializer < Panko::Serializer
  attributes(*WIDE_POST_ATTRIBUTE_NAMES.map(&:to_sym))
end

# Wide rows put the large size above Panko::Config.writer_pool_max_bytes, where the pool
# drops the writer after the call.
benchmark_scenario "Response wide", type: :wide_posts do |records|
  {
    "array_serializer/to_json" => -> {
      Panko::ArraySerializer.new(records, each_serializer: ResponseWidePostPankoSerializer).to_json
    },
    "response/array_serializer" => -> {
      Panko::Response.new(
        success: true,
        posts: Panko::ArraySerializer.new(records, each_serializer: ResponseWidePostPankoSerializer)
      ).to_json
    }
  }
end

record = DATASETS.fetch(:posts).first

benchmark "Response size=1/serializer/serialize_to_json" do
  ResponsePostPankoSerializer.new.serialize_to_json(record)
end

benchmark "Response size=1/response/serializer" do
  Panko::Response.create { |r| {success: true, post: r.serializer(record, ResponsePostPankoSerializer)} }.to_json
end

benchmark "Response size=1/response/json_value" do
  Panko::Response.new(
    success: true,
    post: Panko::JsonValue.from(ResponsePostPankoSerializer.new.serialize_to_json(record))
  ).to_json
end
