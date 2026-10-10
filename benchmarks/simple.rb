# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# model: is set so the engine rows take the specialized path, as Panko does for AR records.

SIMPLE_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "SimplePostBenchSerializer",
  model: Bench::Post,
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

CODE_GEN_JSON_SIMPLE = Panko::CodeGen.compile(SIMPLE_DESCRIPTOR, output: :json).new(descriptor: SIMPLE_DESCRIPTOR)
CODE_GEN_HASH_SIMPLE = Panko::CodeGen.compile(SIMPLE_DESCRIPTOR, output: :hash).new(descriptor: SIMPLE_DESCRIPTOR)

class SimplePostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
end

class SimplePostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title, :body, :views, :published
end

Targets::CODE_GEN_JSON[:simple] = ->(records) { CODE_GEN_JSON_SIMPLE.serialize_many(records) }
Targets::CODE_GEN_HASH[:simple] = ->(records) { CODE_GEN_HASH_SIMPLE.serialize_many(records) }
Targets::PANKO_JSON[:simple] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: SimplePostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:simple] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: SimplePostPankoSerializer).to_a }
Targets::OJ_JSON[:simple] = ->(records) { SimplePostOjSerializer.many(records).to_s }
Targets::PLAIN_JSON[:simple] = ->(records) { records.map(&:as_json).to_json }
Targets::PLAIN_HASH[:simple] = ->(records) { records.map(&:as_json) }

benchmark_scenario "Simple", type: :posts do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:simple].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:simple].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:simple].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:simple].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:simple].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:simple].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:simple].call(records) }
  }
end
