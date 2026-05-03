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
#
# The 71 fields (`:id` + 70 `WIDE_POST_ATTRIBUTE_NAMES`) cross the
# `Filter::Indexed::INDEXED_BITS_THRESHOLD` (63), so the with-filter rows
# below exercise the **Array** representation of `Filter::Indexed` — the
# only production bench that does. Bits rep coverage lives in
# `filter_only.rb` / `filter_except.rb` (5 fields).

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

# Filter narrowing for the with-filter rows. Three sample fields out of 71
# — keep `:only` short to mirror typical query-string usage; `:except` drops
# the same three so the resulting field set is the inverse.
WIDE_ATTRIBUTES_ONLY_KEYS = %i[id s_01 i_01].freeze
WIDE_ATTRIBUTES_EXCEPT_KEYS = %i[s_01 s_02 s_03].freeze

class WideAttributesPostPankoSerializer < Panko::Serializer
  attributes(*WIDE_ATTRIBUTES_PANKO_NAMES)
end

class WideAttributesPostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes(*WIDE_ATTRIBUTES_PANKO_NAMES)
end

# --- Target registry entries ----------------------------------------------

Targets::SCG_JSON[:wide_attributes] = ->(records) { SCG_JSON_WIDE_ATTRIBUTES.serialize_many(records) }
Targets::SCG_HASH[:wide_attributes] = ->(records) { SCG_HASH_WIDE_ATTRIBUTES.serialize_many(records) }
Targets::SCG_JSON[:wide_attributes_with_only] = ->(records) { SCG_JSON_WIDE_ATTRIBUTES.serialize_many(records, filters: {only: WIDE_ATTRIBUTES_ONLY_KEYS}) }
Targets::SCG_HASH[:wide_attributes_with_only] = ->(records) { SCG_HASH_WIDE_ATTRIBUTES.serialize_many(records, filters: {only: WIDE_ATTRIBUTES_ONLY_KEYS}) }
Targets::SCG_JSON[:wide_attributes_with_except] = ->(records) { SCG_JSON_WIDE_ATTRIBUTES.serialize_many(records, filters: {except: WIDE_ATTRIBUTES_EXCEPT_KEYS}) }
Targets::SCG_HASH[:wide_attributes_with_except] = ->(records) { SCG_HASH_WIDE_ATTRIBUTES.serialize_many(records, filters: {except: WIDE_ATTRIBUTES_EXCEPT_KEYS}) }
Targets::PANKO_JSON[:wide_attributes] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: WideAttributesPostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:wide_attributes] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: WideAttributesPostPankoSerializer).to_a }
Targets::OJ_JSON[:wide_attributes] = ->(records) { WideAttributesPostOjSerializer.many(records).to_s }
Targets::PLAIN_JSON[:wide_attributes] = ->(records) { records.map(&:as_json).to_json }
Targets::PLAIN_HASH[:wide_attributes] = ->(records) { records.map(&:as_json) }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "WideAttributes", type: :wide_posts do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:wide_attributes].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:wide_attributes].call(records) },
    "serializers_code_gen/json[with-only]" => -> { Targets::SCG_JSON[:wide_attributes_with_only].call(records) },
    "serializers_code_gen/hash[with-only]" => -> { Targets::SCG_HASH[:wide_attributes_with_only].call(records) },
    "serializers_code_gen/json[with-except]" => -> { Targets::SCG_JSON[:wide_attributes_with_except].call(records) },
    "serializers_code_gen/hash[with-except]" => -> { Targets::SCG_HASH[:wide_attributes_with_except].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:wide_attributes].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:wide_attributes].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:wide_attributes].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:wide_attributes].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:wide_attributes].call(records) }
  }
end
