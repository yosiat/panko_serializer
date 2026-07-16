# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- CodeGenSkipElision — engine-only --------------------------------------------
# Two Descriptors with identical shape — one MethodAttribute returning
# `Panko::CodeGen::SKIP` for half the records (id-even), and one
# control returning the same value unconditionally. Comparing the two
# pins the cost of the SKIP-handling guard
# (`unless value.equal?(Panko::CodeGen::SKIP)`) versus the cost of
# always emitting, so SKIP overhead is no longer buried in the
# method_attribute.rb scenario average.
#
# Only carries `code_gen/*` rows — there's no panko / oj
# equivalent of SKIP (panko's idiom is conditional `if:` on attributes,
# which is a different precedence-ladder shape).

CODE_GEN_SKIP_FIRES_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "CodeGenSkipFiresPostBenchSerializer",
  model: Bench::Post,
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

# --- Target registry entries ----------------------------------------------
# n/a — panko / oj_serializers / plain rows omitted; this scenario compares
# engine variants against each other only.

Targets::CODE_GEN_JSON[:code_gen_skip_elision_fires_half] = ->(records) { CODE_GEN_JSON_SKIP_FIRES.serialize_many(records) }
Targets::CODE_GEN_HASH[:code_gen_skip_elision_fires_half] = ->(records) { CODE_GEN_HASH_SKIP_FIRES.serialize_many(records) }
Targets::CODE_GEN_JSON[:code_gen_skip_elision_never_fires] = ->(records) { CODE_GEN_JSON_SKIP_NEVER.serialize_many(records) }
Targets::CODE_GEN_HASH[:code_gen_skip_elision_never_fires] = ->(records) { CODE_GEN_HASH_SKIP_NEVER.serialize_many(records) }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "CodeGenSkipElision", type: :posts do |records|
  {
    "code_gen/json[skip_fires_half]" => -> { Targets::CODE_GEN_JSON[:code_gen_skip_elision_fires_half].call(records) },
    "code_gen/hash[skip_fires_half]" => -> { Targets::CODE_GEN_HASH[:code_gen_skip_elision_fires_half].call(records) },
    "code_gen/json[skip_never_fires]" => -> { Targets::CODE_GEN_JSON[:code_gen_skip_elision_never_fires].call(records) },
    "code_gen/hash[skip_never_fires]" => -> { Targets::CODE_GEN_HASH[:code_gen_skip_elision_never_fires].call(records) }
  }
end
