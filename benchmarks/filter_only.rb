# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- FilterOnly-shape — phase-2 scenario ----------------------------------
# Phase-2 (S14.1–S14.4) shipped the filter machinery; the engine rows now come
# in two flavors so the canonical bench captures both rules from
# `phase_2_report.md § 2`:
#
#   * `code_gen/{json,hash}` — `filters: nil` baseline. Anchors
#     rule 1 (phase-1 baseline integrity, 5%) — these rows compare to the
#     engine-side numbers in `phase_1_report.md § 3.1.7`, where the phase-1
#     contract was `filters: nil` (every attribute emitted).
#   * `code_gen/{json,hash}[with-only]` — `filters: {only:
#     [:id, :title]}`. Anchors rule 2 (verdict-cell sanity, ±10%) — these
#     rows compare to the S13 verdict cell in
#     `filter_experiments_results.md § 6` (production codegen of the
#     `indexed × single_path` cell from the experiment overlay).
#
# The panko/* and oj_serializers/json rows narrow the attribute set
# directly — for panko that's the runtime `only:` kwarg on
# `ArraySerializer`; oj_serializers has no runtime only:/except:, so the
# idiomatic equivalent is a serializer class with the desired attribute
# set baked in.
#
# Note: plain/* rows are omitted — plain has no filter primitive.

FILTER_ONLY_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "FilterOnlyPostBenchSerializer",
  model: Bench::Post,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :title, source: :title),
    Panko::CodeGen::Attribute.new(name: :body, source: :body),
    Panko::CodeGen::Attribute.new(name: :views, source: :views),
    Panko::CodeGen::Attribute.new(name: :published, source: :published)
  ],
  method_attributes: [],
  associations: []
)

CODE_GEN_JSON_FILTER_ONLY = Panko::CodeGen.compile(FILTER_ONLY_DESCRIPTOR, output: :json).new(descriptor: FILTER_ONLY_DESCRIPTOR)
CODE_GEN_HASH_FILTER_ONLY = Panko::CodeGen.compile(FILTER_ONLY_DESCRIPTOR, output: :hash).new(descriptor: FILTER_ONLY_DESCRIPTOR)

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

Targets::CODE_GEN_JSON[:filter_only] = ->(records) { CODE_GEN_JSON_FILTER_ONLY.serialize_many(records, filters: nil) }
Targets::CODE_GEN_HASH[:filter_only] = ->(records) { CODE_GEN_HASH_FILTER_ONLY.serialize_many(records, filters: nil) }
Targets::CODE_GEN_JSON[:filter_only_with_only] = ->(records) { CODE_GEN_JSON_FILTER_ONLY.serialize_many(records, filters: {only: FILTER_ONLY_KEYS}) }
Targets::CODE_GEN_HASH[:filter_only_with_only] = ->(records) { CODE_GEN_HASH_FILTER_ONLY.serialize_many(records, filters: {only: FILTER_ONLY_KEYS}) }
Targets::PANKO_JSON[:filter_only] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterOnlyPostPankoSerializer, only: FILTER_ONLY_KEYS).to_json }
Targets::PANKO_OBJECT[:filter_only] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterOnlyPostPankoSerializer, only: FILTER_ONLY_KEYS).to_a }
Targets::OJ_JSON[:filter_only] = ->(records) { FilterOnlyPostOjSerializer.many(records).to_s }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "FilterOnly", type: :posts do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:filter_only].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:filter_only].call(records) },
    "code_gen/json[with-only]" => -> { Targets::CODE_GEN_JSON[:filter_only_with_only].call(records) },
    "code_gen/hash[with-only]" => -> { Targets::CODE_GEN_HASH[:filter_only_with_only].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:filter_only].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:filter_only].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:filter_only].call(records) }
    # n/a — plain has no filter primitive
  }
end
