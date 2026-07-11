# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- ScgSkipElision — scg-only --------------------------------------------
# Two Descriptors with identical shape — one MethodAttribute returning
# `Panko::CodeGen::SKIP` for half the records (id-even), and one
# control returning the same value unconditionally. Comparing the two
# pins the cost of the SKIP-handling guard
# (`unless value.equal?(Panko::CodeGen::SKIP)`) versus the cost of
# always emitting, so SKIP overhead is no longer buried in the
# method_attribute.rb scenario average.
#
# Only carries `serializers_code_gen/*` rows — there's no panko / oj
# equivalent of SKIP (panko's idiom is conditional `if:` on attributes,
# which is a different precedence-ladder shape).

SCG_SKIP_FIRES_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "ScgSkipFiresPostBenchSerializer",
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

SCG_SKIP_NEVER_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "ScgSkipNeverPostBenchSerializer",
  model: Bench::Post,
  attributes: SCG_SKIP_FIRES_DESCRIPTOR.attributes,
  method_attributes: [
    Panko::CodeGen::MethodAttribute.new(
      name: :computed_value,
      body: ->(record, _context) { record.body.length }
    )
  ],
  associations: []
)

SCG_JSON_SKIP_FIRES = Panko::CodeGen.compile(SCG_SKIP_FIRES_DESCRIPTOR, output: :json).new(descriptor: SCG_SKIP_FIRES_DESCRIPTOR)
SCG_HASH_SKIP_FIRES = Panko::CodeGen.compile(SCG_SKIP_FIRES_DESCRIPTOR, output: :hash).new(descriptor: SCG_SKIP_FIRES_DESCRIPTOR)
SCG_JSON_SKIP_NEVER = Panko::CodeGen.compile(SCG_SKIP_NEVER_DESCRIPTOR, output: :json).new(descriptor: SCG_SKIP_NEVER_DESCRIPTOR)
SCG_HASH_SKIP_NEVER = Panko::CodeGen.compile(SCG_SKIP_NEVER_DESCRIPTOR, output: :hash).new(descriptor: SCG_SKIP_NEVER_DESCRIPTOR)

# --- Target registry entries ----------------------------------------------
# n/a — panko / oj_serializers / plain rows omitted; this scenario compares
# scg variants against each other only.

Targets::SCG_JSON[:scg_skip_elision_fires_half] = ->(records) { SCG_JSON_SKIP_FIRES.serialize_many(records) }
Targets::SCG_HASH[:scg_skip_elision_fires_half] = ->(records) { SCG_HASH_SKIP_FIRES.serialize_many(records) }
Targets::SCG_JSON[:scg_skip_elision_never_fires] = ->(records) { SCG_JSON_SKIP_NEVER.serialize_many(records) }
Targets::SCG_HASH[:scg_skip_elision_never_fires] = ->(records) { SCG_HASH_SKIP_NEVER.serialize_many(records) }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "ScgSkipElision", type: :posts do |records|
  {
    "serializers_code_gen/json[skip_fires_half]" => -> { Targets::SCG_JSON[:scg_skip_elision_fires_half].call(records) },
    "serializers_code_gen/hash[skip_fires_half]" => -> { Targets::SCG_HASH[:scg_skip_elision_fires_half].call(records) },
    "serializers_code_gen/json[skip_never_fires]" => -> { Targets::SCG_JSON[:scg_skip_elision_never_fires].call(records) },
    "serializers_code_gen/hash[skip_never_fires]" => -> { Targets::SCG_HASH[:scg_skip_elision_never_fires].call(records) }
  }
end
