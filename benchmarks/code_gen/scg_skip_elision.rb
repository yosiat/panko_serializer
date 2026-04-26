# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- ScgSkipElision — scg-only --------------------------------------------
# Two Descriptors with identical shape — one MethodAttribute returning
# `SerializersCodeGen::SKIP` for half the records (id-even), and one
# control returning the same value unconditionally. Comparing the two
# pins the cost of the SKIP-handling guard
# (`unless value.equal?(SerializersCodeGen::SKIP)`) versus the cost of
# always emitting, so SKIP overhead is no longer buried in the
# method_attribute.rb scenario average.
#
# Only carries `serializers_code_gen/*` rows — there's no panko / oj
# equivalent of SKIP (panko's idiom is conditional `if:` on attributes,
# which is a different precedence-ladder shape).

SCG_SKIP_FIRES_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "ScgSkipFiresPostBenchSerializer",
  models: [Bench::Post],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :title, source: :title)
  ],
  method_attributes: [
    SerializersCodeGen::MethodAttribute.new(
      name: :computed_value,
      body: ->(record, _context) { record.id.even? ? SerializersCodeGen::SKIP : record.body.length }
    )
  ],
  associations: []
)

SCG_SKIP_NEVER_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "ScgSkipNeverPostBenchSerializer",
  models: [Bench::Post],
  attributes: SCG_SKIP_FIRES_DESCRIPTOR.attributes,
  method_attributes: [
    SerializersCodeGen::MethodAttribute.new(
      name: :computed_value,
      body: ->(record, _context) { record.body.length }
    )
  ],
  associations: []
)

SCG_JSON_SKIP_FIRES = SerializersCodeGen.compile(SCG_SKIP_FIRES_DESCRIPTOR, output: :json).new(descriptor: SCG_SKIP_FIRES_DESCRIPTOR)
SCG_HASH_SKIP_FIRES = SerializersCodeGen.compile(SCG_SKIP_FIRES_DESCRIPTOR, output: :hash).new(descriptor: SCG_SKIP_FIRES_DESCRIPTOR)
SCG_JSON_SKIP_NEVER = SerializersCodeGen.compile(SCG_SKIP_NEVER_DESCRIPTOR, output: :json).new(descriptor: SCG_SKIP_NEVER_DESCRIPTOR)
SCG_HASH_SKIP_NEVER = SerializersCodeGen.compile(SCG_SKIP_NEVER_DESCRIPTOR, output: :hash).new(descriptor: SCG_SKIP_NEVER_DESCRIPTOR)

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
