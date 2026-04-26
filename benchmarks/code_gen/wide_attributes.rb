# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- WideAttributes-shape Descriptor / serializers ------------------------
# Single Bench::WidePost Descriptor carrying ~70 Attributes split across the
# four primitive types AR exposes (string / integer / boolean / decimal /
# date). Stresses per-Field emit/dispatch cost beyond what Panko's existing
# bench covers — the column count is open to refinement (per
# docs/benchmarks.md § Open refinements). Models: [Bench::WidePost] picks
# the specialized path so the scg row goes through the same model-aware
# fast path as panko/{json,object} for an apples-to-apples comparison.

WIDE_ATTRIBUTES_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "WideAttributesPostBenchSerializer",
  models: [Bench::WidePost],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    *WIDE_POST_ATTRIBUTE_NAMES.map { |n| SerializersCodeGen::Attribute.new(name: n.to_sym, source: n.to_sym) }
  ],
  method_attributes: [],
  associations: []
)

SCG_JSON_WIDE_ATTRIBUTES = SerializersCodeGen.compile(WIDE_ATTRIBUTES_DESCRIPTOR, output: :json).new(descriptor: WIDE_ATTRIBUTES_DESCRIPTOR)
SCG_HASH_WIDE_ATTRIBUTES = SerializersCodeGen.compile(WIDE_ATTRIBUTES_DESCRIPTOR, output: :hash).new(descriptor: WIDE_ATTRIBUTES_DESCRIPTOR)

WIDE_ATTRIBUTES_PANKO_NAMES = [:id, *WIDE_POST_ATTRIBUTE_NAMES.map(&:to_sym)].freeze

class WideAttributesPostPankoSerializer < Panko::Serializer
  attributes(*WIDE_ATTRIBUTES_PANKO_NAMES)
end

class WideAttributesPostOjSerializer < OjSerializers::Serializer
  attributes(*WIDE_ATTRIBUTES_PANKO_NAMES)
end

# --- Target registry entries ----------------------------------------------

Targets::SCG_JSON[:wide_attributes] = ->(records) { SCG_JSON_WIDE_ATTRIBUTES.serialize_many(records) }
Targets::SCG_HASH[:wide_attributes] = ->(records) { SCG_HASH_WIDE_ATTRIBUTES.serialize_many(records) }
Targets::PANKO_JSON[:wide_attributes] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: WideAttributesPostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:wide_attributes] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: WideAttributesPostPankoSerializer).to_a }
Targets::OJ_JSON[:wide_attributes] = ->(records) { WideAttributesPostOjSerializer.many_as_json(records) }
Targets::PLAIN_JSON[:wide_attributes] = ->(records) { records.map(&:as_json).to_json }
Targets::PLAIN_HASH[:wide_attributes] = ->(records) { records.map(&:as_json) }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "WideAttributes", type: :wide_post do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:wide_attributes].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:wide_attributes].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:wide_attributes].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:wide_attributes].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:wide_attributes].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:wide_attributes].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:wide_attributes].call(records) }
  }
end
