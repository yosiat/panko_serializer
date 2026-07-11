# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- HasOne-shape Descriptor / serializers --------------------------------
# Post → Author single has_one Association. model: Bench::Post / Bench::Author
# picks the specialized path on both sides so the scg row goes through the
# same model-aware fast path as panko/{json,object} for an apples-to-apples
# comparison.

HAS_ONE_AUTHOR_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "HasOneAuthorBenchSerializer",
  model: Bench::Author,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :name, source: :name)
  ],
  method_attributes: [],
  associations: []
)

HAS_ONE_POST_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "HasOnePostBenchSerializer",
  model: Bench::Post,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :title, source: :title),
    Panko::CodeGen::Attribute.new(name: :body, source: :body)
  ],
  method_attributes: [],
  associations: [
    Panko::CodeGen::Association.new(
      name: :author,
      kind: :has_one,
      descriptor: HAS_ONE_AUTHOR_DESCRIPTOR
    )
  ]
)

SCG_JSON_HAS_ONE = Panko::CodeGen.compile(HAS_ONE_POST_DESCRIPTOR, output: :json).new(descriptor: HAS_ONE_POST_DESCRIPTOR)
SCG_HASH_HAS_ONE = Panko::CodeGen.compile(HAS_ONE_POST_DESCRIPTOR, output: :hash).new(descriptor: HAS_ONE_POST_DESCRIPTOR)

class HasOneAuthorPankoSerializer < Panko::Serializer
  attributes :id, :name
end

class HasOnePostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body
  has_one :author, serializer: HasOneAuthorPankoSerializer
end

class HasOneAuthorOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :name
end

class HasOnePostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title, :body
  has_one :author, serializer: HasOneAuthorOjSerializer
end

# --- Target registry entries ----------------------------------------------

Targets::SCG_JSON[:has_one] = ->(records) { SCG_JSON_HAS_ONE.serialize_many(records) }
Targets::SCG_HASH[:has_one] = ->(records) { SCG_HASH_HAS_ONE.serialize_many(records) }
Targets::PANKO_JSON[:has_one] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: HasOnePostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:has_one] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: HasOnePostPankoSerializer).to_a }
Targets::OJ_JSON[:has_one] = ->(records) { HasOnePostOjSerializer.many(records).to_s }
Targets::PLAIN_JSON[:has_one] = ->(records) { records.map { |r| r.as_json(include: :author) }.to_json }
Targets::PLAIN_HASH[:has_one] = ->(records) { records.map { |r| r.as_json(include: :author) } }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "HasOne", type: :posts do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:has_one].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:has_one].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:has_one].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:has_one].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:has_one].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:has_one].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:has_one].call(records) }
  }
end
