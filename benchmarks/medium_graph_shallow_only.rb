# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# Reads the eager-loaded comments, so no query runs inside the measured block.
class Bench::Post
  def first_comment
    comments.first
  end
end

MEDIUM_GRAPH_AUTHOR_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "MediumGraphAuthorBenchSerializer",
  model: Bench::Author,
  parent_class: Bench::BaseSerializer,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :name, source: :name),
    Panko::CodeGen::Attribute.new(name: :email, source: :email)
  ],
  method_attributes: [],
  associations: []
)

MEDIUM_GRAPH_COMMENT_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "MediumGraphCommentBenchSerializer",
  model: Bench::Comment,
  parent_class: Bench::BaseSerializer,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :body, source: :body)
  ],
  method_attributes: [],
  associations: []
)

MEDIUM_GRAPH_POST_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "MediumGraphPostBenchSerializer",
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
  associations: [
    Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: MEDIUM_GRAPH_AUTHOR_DESCRIPTOR),
    Panko::CodeGen::Association.new(name: :first_comment, kind: :has_one, descriptor: MEDIUM_GRAPH_COMMENT_DESCRIPTOR),
    Panko::CodeGen::Association.new(name: :comments, kind: :has_many, descriptor: MEDIUM_GRAPH_COMMENT_DESCRIPTOR)
  ]
)

CODE_GEN_JSON_MEDIUM_GRAPH = Panko::CodeGen.compile(MEDIUM_GRAPH_POST_DESCRIPTOR, output: :json).new(descriptor: MEDIUM_GRAPH_POST_DESCRIPTOR)
CODE_GEN_HASH_MEDIUM_GRAPH = Panko::CodeGen.compile(MEDIUM_GRAPH_POST_DESCRIPTOR, output: :hash).new(descriptor: MEDIUM_GRAPH_POST_DESCRIPTOR)

class MediumGraphAuthorPankoSerializer < Panko::Serializer
  attributes :id, :name, :email
end

class MediumGraphCommentPankoSerializer < Panko::Serializer
  attributes :id, :body
end

class MediumGraphPostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
  has_one :author, serializer: MediumGraphAuthorPankoSerializer
  has_one :first_comment, serializer: MediumGraphCommentPankoSerializer
  has_many :comments, serializer: MediumGraphCommentPankoSerializer
end

# oj_serializers has no runtime only:/except:, so the narrowed set is baked in.
class MediumGraphAuthorOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :name, :email
end

class MediumGraphPostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title
  has_one :author, serializer: MediumGraphAuthorOjSerializer
end

MEDIUM_GRAPH_SHALLOW_ONLY_KEYS = %i[id title author].freeze

MEDIUM_GRAPH_SHALLOW_ONLY_FILTER = {only: MEDIUM_GRAPH_SHALLOW_ONLY_KEYS}.freeze

Targets::CODE_GEN_JSON[:medium_graph_shallow_only] = ->(records) { CODE_GEN_JSON_MEDIUM_GRAPH.serialize_many(records, filters: nil) }
Targets::CODE_GEN_HASH[:medium_graph_shallow_only] = ->(records) { CODE_GEN_HASH_MEDIUM_GRAPH.serialize_many(records, filters: nil) }
Targets::CODE_GEN_JSON[:medium_graph_shallow_only_with_only] = ->(records) { CODE_GEN_JSON_MEDIUM_GRAPH.serialize_many(records, filters: MEDIUM_GRAPH_SHALLOW_ONLY_FILTER) }
Targets::CODE_GEN_HASH[:medium_graph_shallow_only_with_only] = ->(records) { CODE_GEN_HASH_MEDIUM_GRAPH.serialize_many(records, filters: MEDIUM_GRAPH_SHALLOW_ONLY_FILTER) }
Targets::PANKO_JSON[:medium_graph_shallow_only] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: MediumGraphPostPankoSerializer, only: MEDIUM_GRAPH_SHALLOW_ONLY_KEYS).to_json }
Targets::PANKO_OBJECT[:medium_graph_shallow_only] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: MediumGraphPostPankoSerializer, only: MEDIUM_GRAPH_SHALLOW_ONLY_KEYS).to_a }
Targets::OJ_JSON[:medium_graph_shallow_only] = ->(records) { MediumGraphPostOjSerializer.many(records).to_s }

benchmark_scenario "MediumGraphShallowOnly", type: :posts do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:medium_graph_shallow_only].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:medium_graph_shallow_only].call(records) },
    "code_gen/json[with-only]" => -> { Targets::CODE_GEN_JSON[:medium_graph_shallow_only_with_only].call(records) },
    "code_gen/hash[with-only]" => -> { Targets::CODE_GEN_HASH[:medium_graph_shallow_only_with_only].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:medium_graph_shallow_only].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:medium_graph_shallow_only].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:medium_graph_shallow_only].call(records) }
  }
end
