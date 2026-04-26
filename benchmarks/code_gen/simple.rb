# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- Simple-shape Descriptor / serializers --------------------------------
# Flat Attributes only — no method attributes, no associations, no filters.
# Models: [Bench::Post] picks the specialized path for an apples-to-apples
# comparison against panko/object and panko/json (which always go through
# their own model-aware fast path).

SIMPLE_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "SimplePostBenchSerializer",
  models: [Bench::Post],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :title, source: :title),
    SerializersCodeGen::Attribute.new(name: :body, source: :body),
    SerializersCodeGen::Attribute.new(name: :views, source: :views),
    SerializersCodeGen::Attribute.new(name: :published, source: :published)
  ],
  method_attributes: [],
  associations: []
)

SCG_JSON_SIMPLE = SerializersCodeGen.compile(SIMPLE_DESCRIPTOR, output: :json).new(descriptor: SIMPLE_DESCRIPTOR)
SCG_HASH_SIMPLE = SerializersCodeGen.compile(SIMPLE_DESCRIPTOR, output: :hash).new(descriptor: SIMPLE_DESCRIPTOR)

class SimplePostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
end

class SimplePostOjSerializer < OjSerializers::Serializer
  attributes :id, :title, :body, :views, :published
end

# --- Target registry entries ----------------------------------------------

Targets::SCG_JSON[:simple] = ->(records) { SCG_JSON_SIMPLE.serialize_many(records) }
Targets::SCG_HASH[:simple] = ->(records) { SCG_HASH_SIMPLE.serialize_many(records) }
Targets::PANKO_JSON[:simple] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: SimplePostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:simple] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: SimplePostPankoSerializer).to_a }
Targets::OJ_JSON[:simple] = ->(records) { SimplePostOjSerializer.many_as_json(records) }
Targets::PLAIN_JSON[:simple] = ->(records) { records.map(&:as_json).to_json }
Targets::PLAIN_HASH[:simple] = ->(records) { records.map(&:as_json) }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "Simple", type: :posts do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:simple].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:simple].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:simple].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:simple].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:simple].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:simple].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:simple].call(records) }
  }
end
