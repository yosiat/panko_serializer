# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- FilterExcept-shape — phase-1 scaffolding ONLY ------------------------
# This scenario is scaffolding for S14 (phase-2 filter implementation). The
# scg rows MUST pass `filters: nil` per the phase-1 contract — the
# `filters:` kwarg locks at S2 day 1 and raises NotImplementedError on
# non-nil (`docs/filters.md § Phase-1 behavior`). Phase-2 will flip the
# kwarg to `filters: {except: [:body]}` without restructuring this file.
#
# The panko/* and oj_serializers/json rows DO call their respective
# narrowing primitives — for panko that's the runtime `except:` kwarg on
# `ArraySerializer`; oj_serializers has no runtime only:/except:, so the
# idiomatic equivalent is a serializer class with the omitted attribute
# already absent from the definition. Phase-1 numbers here are
# intentionally apples-to-oranges (scg-no-filter vs panko-with-filter);
# S14 fills the scg side in.
#
# Note: plain/* rows are omitted — plain has no filter primitive.

FILTER_EXCEPT_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "FilterExceptPostBenchSerializer",
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

SCG_JSON_FILTER_EXCEPT = SerializersCodeGen.compile(FILTER_EXCEPT_DESCRIPTOR, output: :json).new(descriptor: FILTER_EXCEPT_DESCRIPTOR)
SCG_HASH_FILTER_EXCEPT = SerializersCodeGen.compile(FILTER_EXCEPT_DESCRIPTOR, output: :hash).new(descriptor: FILTER_EXCEPT_DESCRIPTOR)

class FilterExceptPostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
end

# oj_serializers has no runtime only:/except:; bake the narrowed set in
# (i.e., `body` is already absent from the definition).
class FilterExceptPostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title, :views, :published
end

FILTER_EXCEPT_KEYS = %i[body].freeze

# --- Target registry entries ----------------------------------------------
# n/a — plain has no filter primitive

Targets::SCG_JSON[:filter_except] = ->(records) { SCG_JSON_FILTER_EXCEPT.serialize_many(records, filters: nil) }
Targets::SCG_HASH[:filter_except] = ->(records) { SCG_HASH_FILTER_EXCEPT.serialize_many(records, filters: nil) }
Targets::PANKO_JSON[:filter_except] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterExceptPostPankoSerializer, except: FILTER_EXCEPT_KEYS).to_json }
Targets::PANKO_OBJECT[:filter_except] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterExceptPostPankoSerializer, except: FILTER_EXCEPT_KEYS).to_a }
Targets::OJ_JSON[:filter_except] = ->(records) { FilterExceptPostOjSerializer.many(records).to_s }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "FilterExcept", type: :posts do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:filter_except].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:filter_except].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:filter_except].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:filter_except].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:filter_except].call(records) }
    # n/a — plain has no filter primitive
  }
end
