# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- CodeGenRecursive — engine-only ----------------------------------------------
# Reuses the `recursive_self` Descriptor shape from S8.1: a single
# Bench::Comment Descriptor that names itself through a `has_many :replies`
# Association. The Compiler emits the self-recursion shortcut
# (`@replies_serializer = self`) so the Generated Class never allocates
# a child instance — the whole tree walks through one Generated Class.
#
# Bench dataset is the `:comment_trees` registry entry: roots eager-loaded
# three levels deep (replies → replies → replies) so even the leaf
# grandchildren have their empty replies cache populated and the full
# 1 + 2 + 4 = 7-node tree walks without an N+1 query inside the measured
# block (per docs/benchmarks.md § Fixture data).
#
# Only carries `code_gen/*` rows — there's no equivalent
# panko / oj recursive primitive worth comparing (panko's recursive
# pattern requires a separate intermediate serializer per level, which
# isn't shape-parity with the engine's self-reference).

CODE_GEN_RECURSIVE_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "CodeGenRecursiveCommentBenchSerializer",
  model: Bench::Comment,
  parent_class: Bench::BaseSerializer,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :body, source: :body)
  ],
  method_attributes: [],
  associations: []
)
# Self-reference appended after construction — Data fields are immutable
# but Field-kind arrays are not frozen, so post-construction `<<` is the
# standard idiom for self-recursive Descriptors (mirror of
# `spec/fixtures/descriptors/recursive_self.rb`).
CODE_GEN_RECURSIVE_DESCRIPTOR.associations << Panko::CodeGen::Association.new(
  name: :replies,
  kind: :has_many,
  descriptor: CODE_GEN_RECURSIVE_DESCRIPTOR
)

CODE_GEN_JSON_RECURSIVE = Panko::CodeGen.compile(CODE_GEN_RECURSIVE_DESCRIPTOR, output: :json).new(descriptor: CODE_GEN_RECURSIVE_DESCRIPTOR)
CODE_GEN_HASH_RECURSIVE = Panko::CodeGen.compile(CODE_GEN_RECURSIVE_DESCRIPTOR, output: :hash).new(descriptor: CODE_GEN_RECURSIVE_DESCRIPTOR)

# --- Target registry entries ----------------------------------------------
# n/a — panko / oj_serializers / plain rows omitted; this scenario measures
# the engine's self-recursion shortcut, which has no shape-parity peer.

Targets::CODE_GEN_JSON[:code_gen_recursive] = ->(records) { CODE_GEN_JSON_RECURSIVE.serialize_many(records) }
Targets::CODE_GEN_HASH[:code_gen_recursive] = ->(records) { CODE_GEN_HASH_RECURSIVE.serialize_many(records) }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "CodeGenRecursive", type: :comment_trees do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:code_gen_recursive].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:code_gen_recursive].call(records) }
  }
end
