# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- MethodAttribute-shape Descriptor / serializers -----------------------
# Single Method Attribute computing `body_length` from the post's body. The
# Callable receives `(record, context)` and is invoked once per record per
# call. model: Bench::Post picks the specialized path so the engine row
# goes through the same model-aware fast path as panko/{json,object} for
# an apples-to-apples comparison.

METHOD_ATTRIBUTE_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "MethodAttributePostBenchSerializer",
  model: Bench::Post,
  parent_class: Bench::BaseSerializer,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :title, source: :title)
  ],
  method_attributes: [
    Panko::CodeGen::MethodAttribute.new(
      name: :body_length,
      body: ->(record, _context) { record.body.length }
    )
  ],
  associations: []
)

CODE_GEN_JSON_METHOD_ATTRIBUTE = Panko::CodeGen.compile(METHOD_ATTRIBUTE_DESCRIPTOR, output: :json).new(descriptor: METHOD_ATTRIBUTE_DESCRIPTOR)
CODE_GEN_HASH_METHOD_ATTRIBUTE = Panko::CodeGen.compile(METHOD_ATTRIBUTE_DESCRIPTOR, output: :hash).new(descriptor: METHOD_ATTRIBUTE_DESCRIPTOR)

class MethodAttributePostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body_length

  def body_length
    object.body.length
  end
end

class MethodAttributePostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title

  attribute
  def body_length
    @object.body.length
  end
end

# --- Target registry entries ----------------------------------------------

Targets::CODE_GEN_JSON[:method_attribute] = ->(records) { CODE_GEN_JSON_METHOD_ATTRIBUTE.serialize_many(records) }
Targets::CODE_GEN_HASH[:method_attribute] = ->(records) { CODE_GEN_HASH_METHOD_ATTRIBUTE.serialize_many(records) }
Targets::PANKO_JSON[:method_attribute] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: MethodAttributePostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:method_attribute] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: MethodAttributePostPankoSerializer).to_a }
Targets::OJ_JSON[:method_attribute] = ->(records) { MethodAttributePostOjSerializer.many(records).to_s }
Targets::PLAIN_JSON[:method_attribute] = ->(records) { records.map { |r| {id: r.id, title: r.title, body_length: r.body.length} }.to_json }
Targets::PLAIN_HASH[:method_attribute] = ->(records) { records.map { |r| {id: r.id, title: r.title, body_length: r.body.length} } }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "MethodAttribute", type: :posts do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:method_attribute].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:method_attribute].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:method_attribute].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:method_attribute].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:method_attribute].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:method_attribute].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:method_attribute].call(records) }
  }
end
