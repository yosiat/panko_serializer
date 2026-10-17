# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# model: is set so the engine rows take the specialized path, as Panko does for AR records.

HAS_MANY_COMMENT_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "HasManyCommentBenchSerializer",
  model: Bench::Comment,
  parent_class: Bench::BaseSerializer,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :body, source: :body)
  ],
  method_attributes: [],
  associations: []
)

HAS_MANY_POST_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "HasManyPostBenchSerializer",
  model: Bench::Post,
  parent_class: Bench::BaseSerializer,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :title, source: :title)
  ],
  method_attributes: [],
  associations: [
    Panko::CodeGen::Association.new(
      name: :comments,
      kind: :has_many,
      descriptor: HAS_MANY_COMMENT_DESCRIPTOR
    )
  ]
)

CODE_GEN_JSON_HAS_MANY = Panko::CodeGen.compile(HAS_MANY_POST_DESCRIPTOR, output: :json).new(descriptor: HAS_MANY_POST_DESCRIPTOR)
CODE_GEN_HASH_HAS_MANY = Panko::CodeGen.compile(HAS_MANY_POST_DESCRIPTOR, output: :hash).new(descriptor: HAS_MANY_POST_DESCRIPTOR)

class HasManyCommentPankoSerializer < Panko::Serializer
  attributes :id, :body
end

class HasManyPostPankoSerializer < Panko::Serializer
  attributes :id, :title
  has_many :comments, serializer: HasManyCommentPankoSerializer
end

class HasManyCommentOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :body
end

class HasManyPostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title
  has_many :comments, serializer: HasManyCommentOjSerializer
end

Targets::CODE_GEN_JSON[:has_many] = ->(records) { CODE_GEN_JSON_HAS_MANY.serialize_many(records) }
Targets::CODE_GEN_HASH[:has_many] = ->(records) { CODE_GEN_HASH_HAS_MANY.serialize_many(records) }
Targets::PANKO_JSON[:has_many] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: HasManyPostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:has_many] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: HasManyPostPankoSerializer).to_a }
Targets::OJ_JSON[:has_many] = ->(records) { HasManyPostOjSerializer.many(records).to_s }
Targets::PLAIN_JSON[:has_many] = ->(records) { records.map { |r| r.as_json(include: :comments) }.to_json }
Targets::PLAIN_HASH[:has_many] = ->(records) { records.map { |r| r.as_json(include: :comments) } }

benchmark_scenario "HasMany", type: :posts do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:has_many].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:has_many].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:has_many].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:has_many].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:has_many].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:has_many].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:has_many].call(records) }
  }
end
