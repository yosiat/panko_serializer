# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

CODE_GEN_GENERIC_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "CodeGenGenericPostBenchSerializer",
  model: nil,
  parent_class: Bench::BaseSerializer,
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
  model: Bench::Post,
  parent_class: Bench::BaseSerializer,
  attributes: CODE_GEN_GENERIC_DESCRIPTOR.attributes,
  method_attributes: [],
  associations: []
)

CODE_GEN_JSON_GENERIC = Panko::CodeGen.compile(CODE_GEN_GENERIC_DESCRIPTOR, output: :json).new(descriptor: CODE_GEN_GENERIC_DESCRIPTOR)
CODE_GEN_HASH_GENERIC = Panko::CodeGen.compile(CODE_GEN_GENERIC_DESCRIPTOR, output: :hash).new(descriptor: CODE_GEN_GENERIC_DESCRIPTOR)
CODE_GEN_JSON_SPECIALIZED = Panko::CodeGen.compile(CODE_GEN_SPECIALIZED_DESCRIPTOR, output: :json).new(descriptor: CODE_GEN_SPECIALIZED_DESCRIPTOR)
CODE_GEN_HASH_SPECIALIZED = Panko::CodeGen.compile(CODE_GEN_SPECIALIZED_DESCRIPTOR, output: :hash).new(descriptor: CODE_GEN_SPECIALIZED_DESCRIPTOR)

class CodeGenGvsSPostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
end

Targets::CODE_GEN_JSON[:code_gen_generic_vs_specialized_generic] = ->(records) { CODE_GEN_JSON_GENERIC.serialize_many(records) }
Targets::CODE_GEN_HASH[:code_gen_generic_vs_specialized_generic] = ->(records) { CODE_GEN_HASH_GENERIC.serialize_many(records) }
Targets::CODE_GEN_JSON[:code_gen_generic_vs_specialized_specialized] = ->(records) { CODE_GEN_JSON_SPECIALIZED.serialize_many(records) }
Targets::CODE_GEN_HASH[:code_gen_generic_vs_specialized_specialized] = ->(records) { CODE_GEN_HASH_SPECIALIZED.serialize_many(records) }
Targets::PANKO_JSON[:code_gen_generic_vs_specialized] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: CodeGenGvsSPostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:code_gen_generic_vs_specialized] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: CodeGenGvsSPostPankoSerializer).to_a }

benchmark_scenario "CodeGenGenericVsSpecialized", type: :posts do |records|
  {
    "code_gen/json[generic]" => -> { Targets::CODE_GEN_JSON[:code_gen_generic_vs_specialized_generic].call(records) },
    "code_gen/hash[generic]" => -> { Targets::CODE_GEN_HASH[:code_gen_generic_vs_specialized_generic].call(records) },
    "code_gen/json[specialized]" => -> { Targets::CODE_GEN_JSON[:code_gen_generic_vs_specialized_specialized].call(records) },
    "code_gen/hash[specialized]" => -> { Targets::CODE_GEN_HASH[:code_gen_generic_vs_specialized_specialized].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:code_gen_generic_vs_specialized].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:code_gen_generic_vs_specialized].call(records) }
  }
end
