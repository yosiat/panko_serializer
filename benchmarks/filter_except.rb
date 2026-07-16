# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- FilterExcept-shape — phase-2 scenario --------------------------------
# Phase-2 (S14.1–S14.4) shipped the filter machinery; the engine rows now come
# in two flavors so the canonical bench captures both rules from
# `phase_2_report.md § 2`:
#
#   * `code_gen/{json,hash}` — `filters: nil` baseline. Anchors
#     rule 1 (phase-1 baseline integrity, 5%) — these rows compare to the
#     engine-side numbers in `phase_1_report.md § 3.1.8`, where the phase-1
#     contract was `filters: nil` (every attribute emitted).
#   * `code_gen/{json,hash}[with-except]` — `filters: {except:
#     [:body]}`. Anchors rule 2 (verdict-cell sanity, ±10%) — these rows
#     compare to the S13 verdict cell in
#     `filter_experiments_results.md § 6` (production codegen of the
#     `indexed × single_path` cell from the experiment overlay).
#
# The panko/* and oj_serializers/json rows narrow the attribute set
# directly — for panko that's the runtime `except:` kwarg on
# `ArraySerializer`; oj_serializers has no runtime only:/except:, so the
# idiomatic equivalent is a serializer class with the omitted attribute
# already absent from the definition.
#
# Note: plain/* rows are omitted — plain has no filter primitive.

FILTER_EXCEPT_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "FilterExceptPostBenchSerializer",
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

CODE_GEN_JSON_FILTER_EXCEPT = Panko::CodeGen.compile(FILTER_EXCEPT_DESCRIPTOR, output: :json).new(descriptor: FILTER_EXCEPT_DESCRIPTOR)
CODE_GEN_HASH_FILTER_EXCEPT = Panko::CodeGen.compile(FILTER_EXCEPT_DESCRIPTOR, output: :hash).new(descriptor: FILTER_EXCEPT_DESCRIPTOR)

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

Targets::CODE_GEN_JSON[:filter_except] = ->(records) { CODE_GEN_JSON_FILTER_EXCEPT.serialize_many(records, filters: nil) }
Targets::CODE_GEN_HASH[:filter_except] = ->(records) { CODE_GEN_HASH_FILTER_EXCEPT.serialize_many(records, filters: nil) }
Targets::CODE_GEN_JSON[:filter_except_with_except] = ->(records) { CODE_GEN_JSON_FILTER_EXCEPT.serialize_many(records, filters: {except: FILTER_EXCEPT_KEYS}) }
Targets::CODE_GEN_HASH[:filter_except_with_except] = ->(records) { CODE_GEN_HASH_FILTER_EXCEPT.serialize_many(records, filters: {except: FILTER_EXCEPT_KEYS}) }
Targets::PANKO_JSON[:filter_except] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterExceptPostPankoSerializer, except: FILTER_EXCEPT_KEYS).to_json }
Targets::PANKO_OBJECT[:filter_except] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterExceptPostPankoSerializer, except: FILTER_EXCEPT_KEYS).to_a }
Targets::OJ_JSON[:filter_except] = ->(records) { FilterExceptPostOjSerializer.many(records).to_s }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "FilterExcept", type: :posts do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:filter_except].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:filter_except].call(records) },
    "code_gen/json[with-except]" => -> { Targets::CODE_GEN_JSON[:filter_except_with_except].call(records) },
    "code_gen/hash[with-except]" => -> { Targets::CODE_GEN_HASH[:filter_except_with_except].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:filter_except].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:filter_except].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:filter_except].call(records) }
    # n/a — plain has no filter primitive
  }
end
