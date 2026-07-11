# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- ScgGenericVsSpecialized — scg-only -----------------------------------
# Same flat shape as simple.rb, two Descriptors: one with `model: nil`
# (Generic path) and one with `model: Bench::Post` (Specialized path).
# Quantifies the Specialized path's payoff (per-Attribute
# `record._read_attribute("name")` vs the Generic-path
# `_write_one_object` dispatch through `record.send(:name)`) on a real
# AR record set.
#
# Carries a `panko/*` row alongside the two scg variants: Panko always
# compiles the Generic path (DescriptorBuilder sets `model: nil`), so
# panko/json ≈ scg[generic] plus Panko's DSL/runtime-seam overhead —
# the overhead the merge adds over the raw engine.

SCG_GENERIC_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "ScgGenericPostBenchSerializer",
  model: nil,
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
  model: Bench::Post,
  attributes: SCG_GENERIC_DESCRIPTOR.attributes,
  method_attributes: [],
  associations: []
)

SCG_JSON_GENERIC = Panko::CodeGen.compile(SCG_GENERIC_DESCRIPTOR, output: :json).new(descriptor: SCG_GENERIC_DESCRIPTOR)
SCG_HASH_GENERIC = Panko::CodeGen.compile(SCG_GENERIC_DESCRIPTOR, output: :hash).new(descriptor: SCG_GENERIC_DESCRIPTOR)
SCG_JSON_SPECIALIZED = Panko::CodeGen.compile(SCG_SPECIALIZED_DESCRIPTOR, output: :json).new(descriptor: SCG_SPECIALIZED_DESCRIPTOR)
SCG_HASH_SPECIALIZED = Panko::CodeGen.compile(SCG_SPECIALIZED_DESCRIPTOR, output: :hash).new(descriptor: SCG_SPECIALIZED_DESCRIPTOR)

class ScgGvsSPostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
end

# --- Target registry entries ----------------------------------------------

Targets::SCG_JSON[:scg_generic_vs_specialized_generic] = ->(records) { SCG_JSON_GENERIC.serialize_many(records) }
Targets::SCG_HASH[:scg_generic_vs_specialized_generic] = ->(records) { SCG_HASH_GENERIC.serialize_many(records) }
Targets::SCG_JSON[:scg_generic_vs_specialized_specialized] = ->(records) { SCG_JSON_SPECIALIZED.serialize_many(records) }
Targets::SCG_HASH[:scg_generic_vs_specialized_specialized] = ->(records) { SCG_HASH_SPECIALIZED.serialize_many(records) }
Targets::PANKO_JSON[:scg_generic_vs_specialized] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: ScgGvsSPostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:scg_generic_vs_specialized] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: ScgGvsSPostPankoSerializer).to_a }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "ScgGenericVsSpecialized", type: :posts do |records|
  {
    "serializers_code_gen/json[generic]" => -> { Targets::SCG_JSON[:scg_generic_vs_specialized_generic].call(records) },
    "serializers_code_gen/hash[generic]" => -> { Targets::SCG_HASH[:scg_generic_vs_specialized_generic].call(records) },
    "serializers_code_gen/json[specialized]" => -> { Targets::SCG_JSON[:scg_generic_vs_specialized_specialized].call(records) },
    "serializers_code_gen/hash[specialized]" => -> { Targets::SCG_HASH[:scg_generic_vs_specialized_specialized].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:scg_generic_vs_specialized].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:scg_generic_vs_specialized].call(records) }
  }
end
