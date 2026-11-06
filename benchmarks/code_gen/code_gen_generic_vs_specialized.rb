# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- CodeGenGenericVsSpecialized - code_gen-only -----------------------------------
# Same flat shape as simple.rb, two Descriptors: one with `models: nil`
# (Generic path) and one with `models: [Bench::Post]` (Specialized path).
# Quantifies the Specialized path's payoff (per-Attribute
# `record._read_attribute("name")` vs the Generic-path
# `_write_one_object` dispatch through `record.send(:name)`) on a real
# AR record set, independently of the cross-target code_gen-vs-panko
# comparison the sanity scenarios cover.
#
# Only carries `code_gen/*` rows - this is an internal
# question about code_gen's own emit shape, not a competitive measurement
# against panko / oj_serializers / plain (per
# docs/benchmarks.md § Directory layout).

CODE_GEN_GENERIC_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "CodeGenGenericPostBenchSerializer",
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

CODE_GEN_SPECIALIZED_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "CodeGenSpecializedPostBenchSerializer",
  models: [Bench::Post],
  attributes: CODE_GEN_GENERIC_DESCRIPTOR.attributes,
  method_attributes: [],
  associations: []
)

CODE_GEN_JSON_GENERIC = Panko::CodeGen.compile(CODE_GEN_GENERIC_DESCRIPTOR, output: :json).new(descriptor: CODE_GEN_GENERIC_DESCRIPTOR)
CODE_GEN_HASH_GENERIC = Panko::CodeGen.compile(CODE_GEN_GENERIC_DESCRIPTOR, output: :hash).new(descriptor: CODE_GEN_GENERIC_DESCRIPTOR)
CODE_GEN_JSON_SPECIALIZED = Panko::CodeGen.compile(CODE_GEN_SPECIALIZED_DESCRIPTOR, output: :json).new(descriptor: CODE_GEN_SPECIALIZED_DESCRIPTOR)
CODE_GEN_HASH_SPECIALIZED = Panko::CodeGen.compile(CODE_GEN_SPECIALIZED_DESCRIPTOR, output: :hash).new(descriptor: CODE_GEN_SPECIALIZED_DESCRIPTOR)

# --- Target registry entries ----------------------------------------------
# n/a - panko / oj_serializers / plain rows omitted; this scenario compares
# code_gen variants against each other only.

Targets::CODE_GEN_JSON[:code_gen_generic_vs_specialized_generic] = ->(records) { CODE_GEN_JSON_GENERIC.serialize_many(records) }
Targets::CODE_GEN_HASH[:code_gen_generic_vs_specialized_generic] = ->(records) { CODE_GEN_HASH_GENERIC.serialize_many(records) }
Targets::CODE_GEN_JSON[:code_gen_generic_vs_specialized_specialized] = ->(records) { CODE_GEN_JSON_SPECIALIZED.serialize_many(records) }
Targets::CODE_GEN_HASH[:code_gen_generic_vs_specialized_specialized] = ->(records) { CODE_GEN_HASH_SPECIALIZED.serialize_many(records) }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "CodeGenGenericVsSpecialized", type: :posts do |records|
  {
    "code_gen/json[generic]" => -> { Targets::CODE_GEN_JSON[:code_gen_generic_vs_specialized_generic].call(records) },
    "code_gen/hash[generic]" => -> { Targets::CODE_GEN_HASH[:code_gen_generic_vs_specialized_generic].call(records) },
    "code_gen/json[specialized]" => -> { Targets::CODE_GEN_JSON[:code_gen_generic_vs_specialized_specialized].call(records) },
    "code_gen/hash[specialized]" => -> { Targets::CODE_GEN_HASH[:code_gen_generic_vs_specialized_specialized].call(records) }
  }
end
