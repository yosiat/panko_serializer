# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# Same shape twice: one MethodAttribute returns SKIP for even ids, the other
# never does. Both run the SKIP check; the difference is omitting half the values.

CODE_GEN_SKIP_FIRES_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "CodeGenSkipFiresPostBenchSerializer",
  model: Bench::Post,
  parent_class: Bench::BaseSerializer,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :title, source: :title)
  ],
  method_attributes: [
    Panko::CodeGen::MethodAttribute.new(
      name: :computed_value,
      body: ->(record, _context) { record.id.even? ? Panko::CodeGen::SKIP : record.body.length }
    )
  ],
  associations: []
)

CODE_GEN_SKIP_NEVER_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "CodeGenSkipNeverPostBenchSerializer",
  model: Bench::Post,
  parent_class: Bench::BaseSerializer,
  attributes: CODE_GEN_SKIP_FIRES_DESCRIPTOR.attributes,
  method_attributes: [
    Panko::CodeGen::MethodAttribute.new(
      name: :computed_value,
      body: ->(record, _context) { record.body.length }
    )
  ],
  associations: []
)

CODE_GEN_JSON_SKIP_FIRES = Panko::CodeGen.compile(CODE_GEN_SKIP_FIRES_DESCRIPTOR, output: :json).new(descriptor: CODE_GEN_SKIP_FIRES_DESCRIPTOR)
CODE_GEN_HASH_SKIP_FIRES = Panko::CodeGen.compile(CODE_GEN_SKIP_FIRES_DESCRIPTOR, output: :hash).new(descriptor: CODE_GEN_SKIP_FIRES_DESCRIPTOR)
CODE_GEN_JSON_SKIP_NEVER = Panko::CodeGen.compile(CODE_GEN_SKIP_NEVER_DESCRIPTOR, output: :json).new(descriptor: CODE_GEN_SKIP_NEVER_DESCRIPTOR)
CODE_GEN_HASH_SKIP_NEVER = Panko::CodeGen.compile(CODE_GEN_SKIP_NEVER_DESCRIPTOR, output: :hash).new(descriptor: CODE_GEN_SKIP_NEVER_DESCRIPTOR)

Targets::CODE_GEN_JSON[:code_gen_skip_elision_fires_half] = ->(records) { CODE_GEN_JSON_SKIP_FIRES.serialize_many(records) }
Targets::CODE_GEN_HASH[:code_gen_skip_elision_fires_half] = ->(records) { CODE_GEN_HASH_SKIP_FIRES.serialize_many(records) }
Targets::CODE_GEN_JSON[:code_gen_skip_elision_never_fires] = ->(records) { CODE_GEN_JSON_SKIP_NEVER.serialize_many(records) }
Targets::CODE_GEN_HASH[:code_gen_skip_elision_never_fires] = ->(records) { CODE_GEN_HASH_SKIP_NEVER.serialize_many(records) }

benchmark_scenario "CodeGenSkipElision", type: :posts do |records|
  {
    "code_gen/json[skip_fires_half]" => -> { Targets::CODE_GEN_JSON[:code_gen_skip_elision_fires_half].call(records) },
    "code_gen/hash[skip_fires_half]" => -> { Targets::CODE_GEN_HASH[:code_gen_skip_elision_fires_half].call(records) },
    "code_gen/json[skip_never_fires]" => -> { Targets::CODE_GEN_JSON[:code_gen_skip_elision_never_fires].call(records) },
    "code_gen/hash[skip_never_fires]" => -> { Targets::CODE_GEN_HASH[:code_gen_skip_elision_never_fires].call(records) }
  }
end
