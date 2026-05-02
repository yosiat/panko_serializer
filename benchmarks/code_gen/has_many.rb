# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- HasMany-shape Descriptor / serializers -------------------------------
# Post → Comments has_many Association. Models: [Bench::Post] /
# [Bench::Comment] picks the specialized path on both sides so the scg row
# goes through the same model-aware fast path as panko/{json,object} for an
# apples-to-apples comparison.

HAS_MANY_COMMENT_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "HasManyCommentBenchSerializer",
  models: [Bench::Comment],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :body, source: :body)
  ],
  method_attributes: [],
  associations: []
)

HAS_MANY_POST_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "HasManyPostBenchSerializer",
  models: [Bench::Post],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :title, source: :title)
  ],
  method_attributes: [],
  associations: [
    SerializersCodeGen::Association.new(
      name: :comments,
      kind: :has_many,
      descriptor: HAS_MANY_COMMENT_DESCRIPTOR
    )
  ]
)

SCG_JSON_HAS_MANY = SerializersCodeGen.compile(HAS_MANY_POST_DESCRIPTOR, output: :json).new(descriptor: HAS_MANY_POST_DESCRIPTOR)
SCG_HASH_HAS_MANY = SerializersCodeGen.compile(HAS_MANY_POST_DESCRIPTOR, output: :hash).new(descriptor: HAS_MANY_POST_DESCRIPTOR)

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

# --- Target registry entries ----------------------------------------------

Targets::SCG_JSON[:has_many] = ->(records) { SCG_JSON_HAS_MANY.serialize_many(records) }
Targets::SCG_HASH[:has_many] = ->(records) { SCG_HASH_HAS_MANY.serialize_many(records) }
Targets::PANKO_JSON[:has_many] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: HasManyPostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:has_many] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: HasManyPostPankoSerializer).to_a }
Targets::OJ_JSON[:has_many] = ->(records) { HasManyPostOjSerializer.many(records).to_s }
Targets::PLAIN_JSON[:has_many] = ->(records) { records.map { |r| r.as_json(include: :comments) }.to_json }
Targets::PLAIN_HASH[:has_many] = ->(records) { records.map { |r| r.as_json(include: :comments) } }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "HasMany", type: :posts do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:has_many].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:has_many].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:has_many].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:has_many].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:has_many].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:has_many].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:has_many].call(records) }
  }
end
