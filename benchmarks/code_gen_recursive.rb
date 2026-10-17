# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

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
# Appended after construction: the Descriptor must exist before an Association can name it.
CODE_GEN_RECURSIVE_DESCRIPTOR.associations << Panko::CodeGen::Association.new(
  name: :replies,
  kind: :has_many,
  descriptor: CODE_GEN_RECURSIVE_DESCRIPTOR
)

CODE_GEN_JSON_RECURSIVE = Panko::CodeGen.compile(CODE_GEN_RECURSIVE_DESCRIPTOR, output: :json).new(descriptor: CODE_GEN_RECURSIVE_DESCRIPTOR)
CODE_GEN_HASH_RECURSIVE = Panko::CodeGen.compile(CODE_GEN_RECURSIVE_DESCRIPTOR, output: :hash).new(descriptor: CODE_GEN_RECURSIVE_DESCRIPTOR)

Targets::CODE_GEN_JSON[:code_gen_recursive] = ->(records) { CODE_GEN_JSON_RECURSIVE.serialize_many(records) }
Targets::CODE_GEN_HASH[:code_gen_recursive] = ->(records) { CODE_GEN_HASH_RECURSIVE.serialize_many(records) }

benchmark_scenario "CodeGenRecursive", type: :comment_trees do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:code_gen_recursive].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:code_gen_recursive].call(records) }
  }
end
