# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- HasMany-shape Descriptor / serializers -------------------------------
# Post → Comments has_many Association. model: Bench::Post / Bench::Comment
# picks the specialized path on both sides so the engine row goes through the
# same model-aware fast path as panko/{json,object} for an apples-to-apples
# comparison.

HAS_MANY_COMMENT_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "HasManyCommentBenchSerializer",
  model: Bench::Comment,
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

# --- Target registry entries ----------------------------------------------

Targets::CODE_GEN_JSON[:has_many] = ->(records) { CODE_GEN_JSON_HAS_MANY.serialize_many(records) }
Targets::CODE_GEN_HASH[:has_many] = ->(records) { CODE_GEN_HASH_HAS_MANY.serialize_many(records) }
Targets::PANKO_JSON[:has_many] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: HasManyPostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:has_many] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: HasManyPostPankoSerializer).to_a }
Targets::OJ_JSON[:has_many] = ->(records) { HasManyPostOjSerializer.many(records).to_s }
Targets::PLAIN_JSON[:has_many] = ->(records) { records.map { |r| r.as_json(include: :comments) }.to_json }
Targets::PLAIN_HASH[:has_many] = ->(records) { records.map { |r| r.as_json(include: :comments) } }

# --- Scenario -------------------------------------------------------------

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
