# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- FilterOnly-shape — phase-1 scaffolding ONLY --------------------------
# This scenario is scaffolding for S14 (phase-2 filter implementation). The
# scg rows MUST pass `filters: nil` per the phase-1 contract — the
# `filters:` kwarg locks at S2 day 1 and raises NotImplementedError on
# non-nil (`docs/filters.md § Phase-1 behavior`). Phase-2 will flip the
# kwarg to `filters: {only: [:id, :title]}` without restructuring this
# file.
#
# The panko/* and oj_serializers/json rows DO call their respective
# narrowing primitives — for panko that's the runtime `only:` kwarg on
# `ArraySerializer`; oj_serializers has no runtime only:/except:, so the
# idiomatic equivalent is a serializer class with the desired attribute
# set baked in (which is what an oj_serializers user would actually
# write). Phase-1 numbers here are intentionally apples-to-oranges
# (scg-no-filter vs panko-with-filter); S14 fills the scg side in.
#
# Note: plain/* rows are omitted — plain has no filter primitive.

FILTER_ONLY_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "FilterOnlyPostBenchSerializer",
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

SCG_JSON_FILTER_ONLY = SerializersCodeGen.compile(FILTER_ONLY_DESCRIPTOR, output: :json).new(descriptor: FILTER_ONLY_DESCRIPTOR)
SCG_HASH_FILTER_ONLY = SerializersCodeGen.compile(FILTER_ONLY_DESCRIPTOR, output: :hash).new(descriptor: FILTER_ONLY_DESCRIPTOR)

class FilterOnlyPostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
end

# oj_serializers has no runtime only:/except:; bake the narrowed set in.
class FilterOnlyPostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title
end

FILTER_ONLY_KEYS = %i[id title].freeze

# --- Target registry entries ----------------------------------------------
# n/a — plain has no filter primitive

Targets::SCG_JSON[:filter_only] = ->(records) { SCG_JSON_FILTER_ONLY.serialize_many(records, filters: nil) }
Targets::SCG_HASH[:filter_only] = ->(records) { SCG_HASH_FILTER_ONLY.serialize_many(records, filters: nil) }
Targets::PANKO_JSON[:filter_only] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterOnlyPostPankoSerializer, only: FILTER_ONLY_KEYS).to_json }
Targets::PANKO_OBJECT[:filter_only] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterOnlyPostPankoSerializer, only: FILTER_ONLY_KEYS).to_a }
Targets::OJ_JSON[:filter_only] = ->(records) { FilterOnlyPostOjSerializer.many(records).to_s }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "FilterOnly", type: :posts do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:filter_only].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:filter_only].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:filter_only].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:filter_only].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:filter_only].call(records) }
    # n/a — plain has no filter primitive
  }
end
