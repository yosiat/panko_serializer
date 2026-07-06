# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- ScgGenericVsSpecialized — scg-only -----------------------------------
# Same flat shape as simple.rb, two Descriptors: one with `models: nil`
# (Generic path) and one with `models: [Bench::Post]` (Specialized path).
# Quantifies the Specialized path's payoff (per-Attribute
# `record._read_attribute("name")` vs the Generic-path
# `_write_one_object` dispatch through `record.send(:name)`) on a real
# AR record set, independently of the cross-target scg-vs-panko
# comparison the sanity scenarios cover.
#
# Only carries `serializers_code_gen/*` rows — this is an internal
# question about scg's own emit shape, not a competitive measurement
# against panko / oj_serializers / plain (per
# docs/benchmarks.md § Directory layout).

SCG_GENERIC_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "ScgGenericPostBenchSerializer",
  models: nil,
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

SCG_SPECIALIZED_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "ScgSpecializedPostBenchSerializer",
  models: [Bench::Post],
  attributes: SCG_GENERIC_DESCRIPTOR.attributes,
  method_attributes: [],
  associations: []
)

SCG_JSON_GENERIC = Panko::CodeGen.compile(SCG_GENERIC_DESCRIPTOR, output: :json).new(descriptor: SCG_GENERIC_DESCRIPTOR)
SCG_HASH_GENERIC = Panko::CodeGen.compile(SCG_GENERIC_DESCRIPTOR, output: :hash).new(descriptor: SCG_GENERIC_DESCRIPTOR)
SCG_JSON_SPECIALIZED = Panko::CodeGen.compile(SCG_SPECIALIZED_DESCRIPTOR, output: :json).new(descriptor: SCG_SPECIALIZED_DESCRIPTOR)
SCG_HASH_SPECIALIZED = Panko::CodeGen.compile(SCG_SPECIALIZED_DESCRIPTOR, output: :hash).new(descriptor: SCG_SPECIALIZED_DESCRIPTOR)

# --- Target registry entries ----------------------------------------------
# n/a — panko / oj_serializers / plain rows omitted; this scenario compares
# scg variants against each other only.

Targets::SCG_JSON[:scg_generic_vs_specialized_generic] = ->(records) { SCG_JSON_GENERIC.serialize_many(records) }
Targets::SCG_HASH[:scg_generic_vs_specialized_generic] = ->(records) { SCG_HASH_GENERIC.serialize_many(records) }
Targets::SCG_JSON[:scg_generic_vs_specialized_specialized] = ->(records) { SCG_JSON_SPECIALIZED.serialize_many(records) }
Targets::SCG_HASH[:scg_generic_vs_specialized_specialized] = ->(records) { SCG_HASH_SPECIALIZED.serialize_many(records) }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "ScgGenericVsSpecialized", type: :posts do |records|
  {
    "serializers_code_gen/json[generic]" => -> { Targets::SCG_JSON[:scg_generic_vs_specialized_generic].call(records) },
    "serializers_code_gen/hash[generic]" => -> { Targets::SCG_HASH[:scg_generic_vs_specialized_generic].call(records) },
    "serializers_code_gen/json[specialized]" => -> { Targets::SCG_JSON[:scg_generic_vs_specialized_specialized].call(records) },
    "serializers_code_gen/hash[specialized]" => -> { Targets::SCG_HASH[:scg_generic_vs_specialized_specialized].call(records) }
  }
end
