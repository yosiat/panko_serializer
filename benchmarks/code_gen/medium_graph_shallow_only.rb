# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/targets"

# --- MediumGraphShallowOnly-shape — phase-2 scenario ----------------------
# Mirrors S13 fixture #6.4 (`medium_graph_shallow_only`) verbatim so the
# canonical `serializers_code_gen/json[with-only]` row reproduces the
# `indexed × single_path` verdict cell from `filter_experiments_results.md
# § 6.4` (49.691K @ size=50, 1147.847 @ size=2300, 6 allocs/call). With
# this scenario in the bench, a future `phase_2_report.md`-style run can
# apply rule 2 (verdict-cell sanity, ±10%) numerically — the gap that
# `phase_2_report.md § 6.2` identified and closed at the
# pattern-equivalence level only.
#
# Shape (lifted from `docs/research/filter_experiments_bench.rb`'s
# `GRAPH_*_DESCRIPTOR` block):
#
#   * Post Descriptor — 5 Attributes (id, title, body, views, published) +
#     3 Associations (author has_one, first_comment has_one, comments
#     has_many) = 8 fields, the count that drives `Filter::Indexed` into
#     its Bits representation per the S13 verdict-cell row.
#   * Author Descriptor — 3 Attributes (id, name, email).
#   * Comment Descriptor — 2 Attributes (id, body), shared between the
#     `:first_comment` has_one and `:comments` has_many Associations.
#
# Filter — `{only: %i[id title author]}`. Keeps 3 of 8 top-level fields
# (2 Attributes + the `author` has_one Association); drops the
# `:first_comment` has_one and the `:comments` has_many entirely. This is
# the exact filter S13 measured.
#
# The scg rows come in two flavors so the canonical bench captures both
# rules from `phase_2_report.md § 2`:
#
#   * `serializers_code_gen/{json,hash}` — `filters: nil` baseline.
#     Rule 1 anchor (phase-1 baseline integrity, 5%); the no-filter path
#     emits every Field including the eager-loaded `:comments` has_many.
#   * `serializers_code_gen/{json,hash}[with-only]` — `filters:
#     MEDIUM_GRAPH_SHALLOW_ONLY_FILTER`. Rule 2 anchor (verdict-cell
#     sanity, ±10%); this is the row the issue exists to make
#     reproducible against S13's `indexed × single_path` cell.
#
# The panko/* and oj_serializers/json rows narrow the attribute set
# directly — for panko that's the runtime `only:` kwarg on
# `ArraySerializer`; oj_serializers has no runtime only:/except:, so the
# idiomatic equivalent is a serializer class with the desired attribute
# set baked in (id + title at the Post level + the full author nesting).
#
# Note: plain/* rows are omitted — plain has no filter primitive.

# Method-backed Source for the `:first_comment` has_one Association on
# `MediumGraphPostDescriptor`. Reads from the already-eager-loaded
# `:comments` collection (the `:posts` dataset entry includes
# `.includes(:author, :comments)`) so the call doesn't trigger an N+1
# query inside the measured block. Mirrors the same method on
# `FilterBench::Post` in `docs/research/filter_experiments_bench.rb`.
class Bench::Post
  # Returns the first comment on this post, or nil when there are none.
  # Used as the Source for the :first_comment has_one Association in
  # medium_graph_shallow_only.rb. No query — relies on `:comments`
  # being eager-loaded by the `:posts` dataset.
  #
  # @return [Bench::Comment, nil]
  def first_comment
    comments.first
  end
end

MEDIUM_GRAPH_AUTHOR_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "MediumGraphAuthorBenchSerializer",
  models: [Bench::Author],
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
  models: [Bench::Comment],
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :body, source: :body)
  ],
  method_attributes: [],
  associations: []
)

MEDIUM_GRAPH_POST_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "MediumGraphPostBenchSerializer",
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
    Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: MEDIUM_GRAPH_AUTHOR_DESCRIPTOR),
    Panko::CodeGen::Association.new(name: :first_comment, kind: :has_one, descriptor: MEDIUM_GRAPH_COMMENT_DESCRIPTOR),
    Panko::CodeGen::Association.new(name: :comments, kind: :has_many, descriptor: MEDIUM_GRAPH_COMMENT_DESCRIPTOR)
  ]
)

SCG_JSON_MEDIUM_GRAPH = Panko::CodeGen.compile(MEDIUM_GRAPH_POST_DESCRIPTOR, output: :json).new(descriptor: MEDIUM_GRAPH_POST_DESCRIPTOR)
SCG_HASH_MEDIUM_GRAPH = Panko::CodeGen.compile(MEDIUM_GRAPH_POST_DESCRIPTOR, output: :hash).new(descriptor: MEDIUM_GRAPH_POST_DESCRIPTOR)

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

# oj_serializers has no runtime only:/except:; bake the narrowed set in
# (top-level keeps id + title; the full author nesting; first_comment
# and comments are absent).
class MediumGraphAuthorOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :name, :email
end

class MediumGraphPostOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title
  has_one :author, serializer: MediumGraphAuthorOjSerializer
end

# Top-level narrowed set — keeps id + title + the entire author
# Composition; the `:first_comment` has_one and `:comments` has_many are
# dropped. Used two ways: as the scg filter's `:only` value, and as the
# Panko `only:` kwarg list. Panko threads the `:author` key through to
# the nested AuthorSerializer; with no nested narrowing, all 3 author
# attrs emit.
MEDIUM_GRAPH_SHALLOW_ONLY_KEYS = %i[id title author].freeze

# Matches `FIXTURES[3][:filter_hash]` in
# `docs/research/filter_experiments_bench.rb` verbatim.
MEDIUM_GRAPH_SHALLOW_ONLY_FILTER = {only: MEDIUM_GRAPH_SHALLOW_ONLY_KEYS}.freeze

# --- Target registry entries ----------------------------------------------
# n/a — plain has no filter primitive

Targets::SCG_JSON[:medium_graph_shallow_only] = ->(records) { SCG_JSON_MEDIUM_GRAPH.serialize_many(records, filters: nil) }
Targets::SCG_HASH[:medium_graph_shallow_only] = ->(records) { SCG_HASH_MEDIUM_GRAPH.serialize_many(records, filters: nil) }
Targets::SCG_JSON[:medium_graph_shallow_only_with_only] = ->(records) { SCG_JSON_MEDIUM_GRAPH.serialize_many(records, filters: MEDIUM_GRAPH_SHALLOW_ONLY_FILTER) }
Targets::SCG_HASH[:medium_graph_shallow_only_with_only] = ->(records) { SCG_HASH_MEDIUM_GRAPH.serialize_many(records, filters: MEDIUM_GRAPH_SHALLOW_ONLY_FILTER) }
Targets::PANKO_JSON[:medium_graph_shallow_only] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: MediumGraphPostPankoSerializer, only: MEDIUM_GRAPH_SHALLOW_ONLY_KEYS).to_json }
Targets::PANKO_OBJECT[:medium_graph_shallow_only] = ->(records) { Panko::ArraySerializer.new(records, each_serializer: MediumGraphPostPankoSerializer, only: MEDIUM_GRAPH_SHALLOW_ONLY_KEYS).to_a }
Targets::OJ_JSON[:medium_graph_shallow_only] = ->(records) { MediumGraphPostOjSerializer.many(records).to_s }

# --- Scenario -------------------------------------------------------------

benchmark_scenario "MediumGraphShallowOnly", type: :posts do |records|
  {
    "serializers_code_gen/json" => -> { Targets::SCG_JSON[:medium_graph_shallow_only].call(records) },
    "serializers_code_gen/hash" => -> { Targets::SCG_HASH[:medium_graph_shallow_only].call(records) },
    "serializers_code_gen/json[with-only]" => -> { Targets::SCG_JSON[:medium_graph_shallow_only_with_only].call(records) },
    "serializers_code_gen/hash[with-only]" => -> { Targets::SCG_HASH[:medium_graph_shallow_only_with_only].call(records) },
    "panko/json" => -> { Targets::PANKO_JSON[:medium_graph_shallow_only].call(records) },
    "panko/object" => -> { Targets::PANKO_OBJECT[:medium_graph_shallow_only].call(records) },
    "oj_serializers/json" => -> { Targets::OJ_JSON[:medium_graph_shallow_only].call(records) }
    # n/a — plain has no filter primitive
  }
end
