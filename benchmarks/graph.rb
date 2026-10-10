# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# first_comment and recent_comments serialize some comments a second time on purpose:
# more emitted fields without a bigger schema.

# Both methods read the eager-loaded comments, so no query runs inside the measured block.
class Bench::Post
  def first_comment
    comments.first
  end

  def recent_comments
    comments.last(2)
  end
end

GRAPH_AUTHOR_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "GraphAuthorBenchSerializer",
  model: Bench::Author,
  parent_class: Bench::BaseSerializer,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :name, source: :name)
  ],
  method_attributes: [],
  associations: []
)

GRAPH_COMMENT_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "GraphCommentBenchSerializer",
  model: Bench::Comment,
  parent_class: Bench::BaseSerializer,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :body, source: :body)
  ],
  method_attributes: [],
  associations: []
)

GRAPH_POST_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "GraphPostBenchSerializer",
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
    Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: GRAPH_AUTHOR_DESCRIPTOR),
    Panko::CodeGen::Association.new(name: :first_comment, kind: :has_one, descriptor: GRAPH_COMMENT_DESCRIPTOR),
    Panko::CodeGen::Association.new(name: :comments, kind: :has_many, descriptor: GRAPH_COMMENT_DESCRIPTOR),
    Panko::CodeGen::Association.new(name: :recent_comments, kind: :has_many, descriptor: GRAPH_COMMENT_DESCRIPTOR)
  ]
)

CODE_GEN_JSON_GRAPH = Panko::CodeGen.compile(GRAPH_POST_DESCRIPTOR, output: :json).new(descriptor: GRAPH_POST_DESCRIPTOR)
CODE_GEN_HASH_GRAPH = Panko::CodeGen.compile(GRAPH_POST_DESCRIPTOR, output: :hash).new(descriptor: GRAPH_POST_DESCRIPTOR)

class GraphAuthorPankoSerializer < Panko::Serializer
  attributes :id, :name
end

class GraphCommentPankoSerializer < Panko::Serializer
  attributes :id, :body
end

class GraphPostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
  has_one :author, serializer: GraphAuthorPankoSerializer
  has_one :first_comment, serializer: GraphCommentPankoSerializer
  has_many :comments, serializer: GraphCommentPankoSerializer
  has_many :recent_comments, serializer: GraphCommentPankoSerializer
end

class GraphAuthorOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :name
end

class GraphCommentOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :body
end

class GraphPostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title, :body, :views, :published
  has_one :author, serializer: GraphAuthorOjSerializer
  has_one :first_comment, serializer: GraphCommentOjSerializer
  has_many :comments, serializer: GraphCommentOjSerializer
  has_many :recent_comments, serializer: GraphCommentOjSerializer
end

GRAPH_FILTER_HASH = {
  only: %i[id title author comments],
  author: {only: %i[id]},
  comments: {only: %i[body]}
}.freeze

Targets::CODE_GEN_JSON[:graph] = ->(records) { CODE_GEN_JSON_GRAPH.serialize_many(records) }
Targets::CODE_GEN_HASH[:graph] = ->(records) { CODE_GEN_HASH_GRAPH.serialize_many(records) }
Targets::CODE_GEN_JSON[:graph_with_only] = ->(records) { CODE_GEN_JSON_GRAPH.serialize_many(records, filters: GRAPH_FILTER_HASH) }
Targets::CODE_GEN_HASH[:graph_with_only] = ->(records) { CODE_GEN_HASH_GRAPH.serialize_many(records, filters: GRAPH_FILTER_HASH) }
Targets::PANKO_JSON[:graph] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: GraphPostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:graph] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: GraphPostPankoSerializer).to_a }
Targets::OJ_JSON[:graph] = ->(records) { GraphPostOjSerializer.many(records).to_s }
# Not the same shape as the library rows: the plain rows leave out first_comment and recent_comments.
Targets::PLAIN_JSON[:graph] = ->(records) { records.map { |r| r.as_json(include: [:author, :comments]) }.to_json }
Targets::PLAIN_HASH[:graph] = ->(records) { records.map { |r| r.as_json(include: [:author, :comments]) } }

benchmark_scenario "Graph", type: :posts do |records|
  {
    "code_gen/json" => -> { Targets::CODE_GEN_JSON[:graph].call(records) },
    "code_gen/hash" => -> { Targets::CODE_GEN_HASH[:graph].call(records) },
    "code_gen/json[with-only]" => -> { Targets::CODE_GEN_JSON[:graph_with_only].call(records) },
    "code_gen/hash[with-only]" => -> { Targets::CODE_GEN_HASH[:graph_with_only].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:graph].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:graph].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:graph].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:graph].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:graph].call(records) }
  }
end
