# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- Graph-shape Descriptor / serializers ---------------------------------
# Entrypoint Bench::Post Descriptor with Attributes + multiple has_one +
# multiple has_many — the combined Composition shape Panko's existing bench
# suite lacks. Two has_one Associations (:author, :first_comment) and two
# has_many Associations (:comments, :recent_comments) on the same parent
# stress per-Field dispatch through several nested Generated Classes per
# Record. Models: [Bench::Post] / [Bench::Author] / [Bench::Comment] picks
# the specialized path on every level.
#
# :first_comment and :recent_comments are method-backed Sources defined on
# Bench::Post inline below (they read from the already-eager-loaded
# in-memory `comments` collection so neither call triggers an N+1 query
# inside the measured block). The redundancy — same Comment serialized in
# two has_many rows + once as has_one — is intentional: it inflates the
# per-Field emit count without expanding the schema.

class Bench::Post
  # Returns the first comment on this post, or nil when there are none. Used
  # as the Source for the :first_comment has_one Association in graph.rb. No
  # query — relies on the :comments association already being eager-loaded
  # by the :posts dataset entry.
  #
  # @return [Bench::Comment, nil]
  def first_comment
    comments.first
  end

  # Returns the two most-recent comments on this post (last-2 of the
  # eager-loaded collection). Used as the Source for the :recent_comments
  # has_many Association in graph.rb.
  #
  # @return [Array<Bench::Comment>]
  def recent_comments
    comments.last(2)
  end
end

GRAPH_AUTHOR_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "GraphAuthorBenchSerializer",
  models: [Bench::Author],
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :name, source: :name)
  ],
  method_attributes: [],
  associations: []
)

GRAPH_COMMENT_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "GraphCommentBenchSerializer",
  models: [Bench::Comment],
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :body, source: :body)
  ],
  method_attributes: [],
  associations: []
)

GRAPH_POST_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "GraphPostBenchSerializer",
  models: [Bench::Post],
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

SCG_JSON_GRAPH = Panko::CodeGen.compile(GRAPH_POST_DESCRIPTOR, output: :json).new(descriptor: GRAPH_POST_DESCRIPTOR)
SCG_HASH_GRAPH = Panko::CodeGen.compile(GRAPH_POST_DESCRIPTOR, output: :hash).new(descriptor: GRAPH_POST_DESCRIPTOR)

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

# --- Target registry entries ----------------------------------------------

# Filter narrowing for the with-filter rows. Top-level `:only` keeps two
# Attributes + the two-level Composition (`author` + `comments`); the
# nested entries narrow each child Descriptor to one Attribute. This shape
# exercises the `Filter::Indexed::Bits#child` cache **during emit** — the
# `has_many :comments` walk hoists the resolved child filter out of the
# loop (S14.4) so subsequent records hit the cache without rebuild.
GRAPH_FILTER_HASH = {
  only: %i[id title author comments],
  author: {only: %i[id]},
  comments: {only: %i[body]}
}.freeze

Targets::SCG_JSON[:graph] = ->(records) { SCG_JSON_GRAPH.serialize_many(records) }
Targets::SCG_HASH[:graph] = ->(records) { SCG_HASH_GRAPH.serialize_many(records) }
Targets::SCG_JSON[:graph_with_only] = ->(records) { SCG_JSON_GRAPH.serialize_many(records, filters: GRAPH_FILTER_HASH) }
Targets::SCG_HASH[:graph_with_only] = ->(records) { SCG_HASH_GRAPH.serialize_many(records, filters: GRAPH_FILTER_HASH) }
Targets::PANKO_JSON[:graph] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: GraphPostPankoSerializer).to_json }
Targets::PANKO_OBJECT[:graph] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: GraphPostPankoSerializer).to_a }
Targets::OJ_JSON[:graph] = ->(records) { GraphPostOjSerializer.many(records).to_s }
# n/a — `as_json(include:)` doesn't follow methods like `first_comment` /
# `recent_comments`, so the plain rows can't reach shape parity with the
# library rows. They mirror the AR-relation subset (:author, :comments) as
# the closest "no-library" baseline.
Targets::PLAIN_JSON[:graph] = ->(records) { records.map { |r| r.as_json(include: [:author, :comments]) }.to_json }
Targets::PLAIN_HASH[:graph] = ->(records) { records.map { |r| r.as_json(include: [:author, :comments]) } }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "Graph", type: :posts do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:graph].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:graph].call(records) },
    "serializers_code_gen/json[with-only]" => -> { Targets::SCG_JSON[:graph_with_only].call(records) },
    "serializers_code_gen/hash[with-only]" => -> { Targets::SCG_HASH[:graph_with_only].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:graph].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:graph].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:graph].call(records) },
    "plain/json" => -> { Targets::PLAIN_JSON[:graph].call(records) },
    "plain/hash" => -> { Targets::PLAIN_HASH[:graph].call(records) }
  }
end
