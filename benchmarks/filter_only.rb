# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

FILTER_ONLY_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "FilterOnlyPostBenchSerializer",
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

CODE_GEN_JSON_FILTER_ONLY = Panko::CodeGen.compile(FILTER_ONLY_DESCRIPTOR, output: :json).new(descriptor: FILTER_ONLY_DESCRIPTOR)
CODE_GEN_HASH_FILTER_ONLY = Panko::CodeGen.compile(FILTER_ONLY_DESCRIPTOR, output: :hash).new(descriptor: FILTER_ONLY_DESCRIPTOR)

class FilterOnlyPostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
end

# oj_serializers has no runtime only:/except:, so the narrowed set is baked in.
class FilterOnlyPostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title
end

FILTER_ONLY_KEYS = %i[id title].freeze

Targets::CODE_GEN_JSON[:filter_only] = ->(records) { CODE_GEN_JSON_FILTER_ONLY.serialize_many(records, filters: nil) }
Targets::CODE_GEN_HASH[:filter_only] = ->(records) { CODE_GEN_HASH_FILTER_ONLY.serialize_many(records, filters: nil) }
Targets::CODE_GEN_JSON[:filter_only_with_only] = ->(records) { CODE_GEN_JSON_FILTER_ONLY.serialize_many(records, filters: {only: FILTER_ONLY_KEYS}) }
Targets::CODE_GEN_HASH[:filter_only_with_only] = ->(records) { CODE_GEN_HASH_FILTER_ONLY.serialize_many(records, filters: {only: FILTER_ONLY_KEYS}) }
Targets::PANKO_JSON[:filter_only] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterOnlyPostPankoSerializer, only: FILTER_ONLY_KEYS).to_json }
Targets::PANKO_OBJECT[:filter_only] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: FilterOnlyPostPankoSerializer, only: FILTER_ONLY_KEYS).to_a }
Targets::OJ_JSON[:filter_only] = ->(records) { FilterOnlyPostOjSerializer.many(records).to_s }

benchmark_scenario "FilterOnly", type: :posts do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:filter_only].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:filter_only].call(records) },
    "code_gen/json[with-only]" => -> { Targets::CODE_GEN_JSON[:filter_only_with_only].call(records) },
    "code_gen/hash[with-only]" => -> { Targets::CODE_GEN_HASH[:filter_only_with_only].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:filter_only].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:filter_only].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:filter_only].call(records) }
  }
end
