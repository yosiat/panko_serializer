# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- ScgRecursive — scg-only ----------------------------------------------
# Reuses the `recursive_self` Descriptor shape from S8.1: a single
# Bench::Comment Descriptor that names itself through a `has_many :replies`
# Association. The Compiler emits the self-recursion shortcut
# (`@replies_serializer = self`) so the Generated Class never allocates
# a child instance — the whole tree walks through one Generated Class.
#
# Bench dataset is the `:comment_trees` registry entry: roots eager-loaded
# `replies: :replies` so the full 1 + 2 + 4 = 7-node tree walks without an
# N+1 query inside the measured block (per docs/benchmarks.md § Fixture
# data).
#
# Only carries `serializers_code_gen/*` rows — there's no equivalent
# panko / oj recursive primitive worth comparing (panko's recursive
# pattern requires a separate intermediate serializer per level, which
# isn't shape-parity with scg's self-reference).

SCG_RECURSIVE_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "ScgRecursiveCommentBenchSerializer",
  models: [Bench::Comment],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :body, source: :body)
  ],
  method_attributes: [],
  associations: []
)
# Self-reference appended after construction — Data fields are immutable
# but Field-kind arrays are not frozen, so post-construction `<<` is the
# standard idiom for self-recursive Descriptors (mirror of
# `spec/fixtures/descriptors/recursive_self.rb`).
SCG_RECURSIVE_DESCRIPTOR.associations << SerializersCodeGen::Association.new(
  name: :replies,
  kind: :has_many,
  descriptor: SCG_RECURSIVE_DESCRIPTOR
)

SCG_JSON_RECURSIVE = SerializersCodeGen.compile(SCG_RECURSIVE_DESCRIPTOR, output: :json).new(descriptor: SCG_RECURSIVE_DESCRIPTOR)
SCG_HASH_RECURSIVE = SerializersCodeGen.compile(SCG_RECURSIVE_DESCRIPTOR, output: :hash).new(descriptor: SCG_RECURSIVE_DESCRIPTOR)

# --- Target registry entries ----------------------------------------------
# n/a — panko / oj_serializers / plain rows omitted; this scenario measures
# scg's self-recursion shortcut, which has no shape-parity peer.

Targets::SCG_JSON[:scg_recursive] = ->(records) { SCG_JSON_RECURSIVE.serialize_many(records) }
Targets::SCG_HASH[:scg_recursive] = ->(records) { SCG_HASH_RECURSIVE.serialize_many(records) }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "ScgRecursive", type: :comment_trees do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:scg_recursive].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:scg_recursive].call(records) }
  }
end
