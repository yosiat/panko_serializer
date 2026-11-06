# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

FILTER_EXCEPT_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "FilterExceptPostBenchSerializer",
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

CODE_GEN_JSON_FILTER_EXCEPT = Panko::CodeGen.compile(FILTER_EXCEPT_DESCRIPTOR, output: :json).new(descriptor: FILTER_EXCEPT_DESCRIPTOR)
CODE_GEN_HASH_FILTER_EXCEPT = Panko::CodeGen.compile(FILTER_EXCEPT_DESCRIPTOR, output: :hash).new(descriptor: FILTER_EXCEPT_DESCRIPTOR)

class FilterExceptPostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
end

# oj_serializers has no runtime only:/except:, so the narrowed set is baked in.
class FilterExceptPostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title, :views, :published
end

FILTER_EXCEPT_KEYS = %i[body].freeze

Targets::CODE_GEN_JSON[:filter_except] = ->(records) { CODE_GEN_JSON_FILTER_EXCEPT.serialize_many(records, filters: nil) }
Targets::CODE_GEN_HASH[:filter_except] = ->(records) { CODE_GEN_HASH_FILTER_EXCEPT.serialize_many(records, filters: nil) }
Targets::CODE_GEN_JSON[:filter_except_with_except] = ->(records) { CODE_GEN_JSON_FILTER_EXCEPT.serialize_many(records, filters: {except: FILTER_EXCEPT_KEYS}) }
Targets::CODE_GEN_HASH[:filter_except_with_except] = ->(records) { CODE_GEN_HASH_FILTER_EXCEPT.serialize_many(records, filters: {except: FILTER_EXCEPT_KEYS}) }
Targets::PANKO_JSON[:filter_except] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterExceptPostPankoSerializer, except: FILTER_EXCEPT_KEYS).to_json }
Targets::PANKO_OBJECT[:filter_except] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterExceptPostPankoSerializer, except: FILTER_EXCEPT_KEYS).to_a }
Targets::OJ_JSON[:filter_except] = ->(records) { FilterExceptPostOjSerializer.many(records).to_s }

benchmark_scenario "FilterExcept", type: :posts do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:filter_except].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:filter_except].call(records) },
    "code_gen/json[with-except]" => -> { Targets::CODE_GEN_JSON[:filter_except_with_except].call(records) },
    "code_gen/hash[with-except]" => -> { Targets::CODE_GEN_HASH[:filter_except_with_except].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:filter_except].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:filter_except].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:filter_except].call(records) }
  }
end
