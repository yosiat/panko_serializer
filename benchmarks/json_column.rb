# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# model: is set so the engine rows take the specialized path, as Panko does for AR records.

JSON_COLUMN_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "JsonColumnPostBenchSerializer",
  model: Bench::Post,
  parent_class: Bench::BaseSerializer,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :metadata, source: :metadata)
  ],
  method_attributes: [],
  associations: []
)

CODE_GEN_JSON_JSON_COLUMN = Panko::CodeGen.compile(JSON_COLUMN_DESCRIPTOR, output: :json).new(descriptor: JSON_COLUMN_DESCRIPTOR)
CODE_GEN_HASH_JSON_COLUMN = Panko::CodeGen.compile(JSON_COLUMN_DESCRIPTOR, output: :hash).new(descriptor: JSON_COLUMN_DESCRIPTOR)

class JsonColumnPostPankoSerializer < Panko::Serializer
  attributes :id, :metadata
end

class JsonColumnPostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :metadata
end

Targets::CODE_GEN_JSON[:json_column] = ->(records) { CODE_GEN_JSON_JSON_COLUMN.serialize_many(records) }
Targets::CODE_GEN_HASH[:json_column] = ->(records) { CODE_GEN_HASH_JSON_COLUMN.serialize_many(records) }
Targets::PANKO_JSON[:json_column] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: JsonColumnPostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:json_column] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: JsonColumnPostPankoSerializer).to_a }
Targets::OJ_JSON[:json_column] = ->(records) { JsonColumnPostOjSerializer.many(records).to_s }
Targets::PLAIN_JSON[:json_column] = ->(records) { records.map { |r| {id: r.id, metadata: r.metadata} }.to_json }
Targets::PLAIN_HASH[:json_column] = ->(records) { records.map { |r| {id: r.id, metadata: r.metadata} } }

benchmark_scenario "JsonColumn", type: :posts do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:json_column].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:json_column].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:json_column].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:json_column].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:json_column].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:json_column].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:json_column].call(records) }
  }
end
