# frozen_string_literal: true

require_relative "support/benchmark"

# --- SingleRecord-shape Descriptor / serializers --------------------------
# Single Bench::Post + has_one :author + has_many :comments — exercises the
# one-record APIs (`serialize_one`, `Serializer.one(record)`,
# `record.as_json`) that the rest of the suite doesn't touch (every other
# scenario measures collection throughput at SIZE=50/2300). Mirrors
# benchmarks/graph.rb's shape, slimmed to just :author / :comments.
#
# This file is self-contained: target lambdas inline below the byte-parity
# guard rather than threaded through Targets::*. The registry exists to
# share lambdas across scenarios that reuse the same target definition; a
# single-record-only scenario won't reuse any of these elsewhere.
#
# Output-parity guard at the top aborts before the bench burns CPU if any
# target's emit shape diverges from the reference. Future scenarios
# should mirror this guard.

RECORD = DATASETS.fetch(:posts).first

# --- SCG ------------------------------------------------------------------

SINGLE_AUTHOR_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "SingleRecordAuthorBenchSerializer",
  model: Bench::Author,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :name, source: :name)
  ],
  method_attributes: [],
  associations: []
)

SINGLE_COMMENT_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "SingleRecordCommentBenchSerializer",
  model: Bench::Comment,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :body, source: :body)
  ],
  method_attributes: [],
  associations: []
)

SINGLE_POST_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "SingleRecordPostBenchSerializer",
  model: Bench::Post,
  attributes: [
    Panko::CodeGen::Attribute.new(name: :id, source: :id),
    Panko::CodeGen::Attribute.new(name: :title, source: :title),
    Panko::CodeGen::Attribute.new(name: :body, source: :body),
    Panko::CodeGen::Attribute.new(name: :views, source: :views),
    Panko::CodeGen::Attribute.new(name: :published, source: :published)
  ],
  method_attributes: [],
  associations: [
    Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: SINGLE_AUTHOR_DESCRIPTOR),
    Panko::CodeGen::Association.new(name: :comments, kind: :has_many, descriptor: SINGLE_COMMENT_DESCRIPTOR)
  ]
)

SCG_JSON_SINGLE = Panko::CodeGen.compile(SINGLE_POST_DESCRIPTOR, output: :json).new(descriptor: SINGLE_POST_DESCRIPTOR)
SCG_HASH_SINGLE = Panko::CodeGen.compile(SINGLE_POST_DESCRIPTOR, output: :hash).new(descriptor: SINGLE_POST_DESCRIPTOR)

# --- Panko ----------------------------------------------------------------

class AuthorPankoSerializer < Panko::Serializer
  attributes :id, :name
end

class CommentPankoSerializer < Panko::Serializer
  attributes :id, :body
end

class PostPankoSerializer < Panko::Serializer
  attributes :id, :title, :body, :views, :published
  has_one :author, serializer: AuthorPankoSerializer
  has_many :comments, serializer: CommentPankoSerializer
end

# --- oj_serializers — two trios ------------------------------------------
# `default_format` aliases the class-level `.one`/`.many` shortcut to the
# json (writer) variant and is inherited per-class, so a per-row toggle
# means re-declaring the alias inside the bench loop. Two parallel trios is
# the lighter trade — clarity over clever.

class AuthorOjJsonSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :name
end

class CommentOjJsonSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :body
end

class PostOjJsonSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :title, :body, :views, :published
  has_one :author, serializer: AuthorOjJsonSerializer
  has_many :comments, serializer: CommentOjJsonSerializer
end

class AuthorOjHashSerializer < OjSerializers::Serializer
  attributes :id, :name
end

class CommentOjHashSerializer < OjSerializers::Serializer
  attributes :id, :body
end

class PostOjHashSerializer < OjSerializers::Serializer
  attributes :id, :title, :body, :views, :published
  has_one :author, serializer: AuthorOjHashSerializer
  has_many :comments, serializer: CommentOjHashSerializer
end

# Plain `as_json` returns *every* column by default — Bench::Post carries
# `:metadata`, Bench::Author has `:bench_post_id`, Bench::Comment has
# `:bench_post_id` / `:parent_comment_id` — none of which the serializer
# rows emit. To make the parity guard meaningful we have to constrain the
# plain rows to the same field set the serializers emit; otherwise the
# guard would always fail for trivially "extra columns" reasons. The
# nested-Hash form of `include:` lets us narrow root + nested in one call.
PLAIN_AS_JSON_OPTIONS = {
  only: [:id, :title, :body, :views, :published],
  include: {
    author: {only: [:id, :name]},
    comments: {only: [:id, :body]}
  }
}.freeze

# --- Output-parity guard --------------------------------------------------
# Build the same shape every target would emit, normalize through
# Oj.load(mode: :strict), and abort with a labeled diff if any row
# diverges. Hash-output rows (scg/hash, panko/object, oj_serializers/hash,
# plain/hash) get Oj.dump'd ONLY here so the parity comparison stays
# String-on-String — the bench loop below measures the raw Hash/Writer
# output without that wrap.

parity_outputs = {
  "serializers_code_gen/json" => SCG_JSON_SINGLE.serialize_one(RECORD),
  "serializers_code_gen/hash" => Oj.dump(SCG_HASH_SINGLE.serialize_one(RECORD)),
  "panko/json" => PostPankoSerializer.new.serialize_to_json(RECORD),
  "panko/object" => Oj.dump(PostPankoSerializer.new.serialize(RECORD)),
  "oj_serializers/json" => PostOjJsonSerializer.one(RECORD).to_s,
  "oj_serializers/hash" => Oj.dump(PostOjHashSerializer.one(RECORD)),
  "plain/json" => RECORD.as_json(PLAIN_AS_JSON_OPTIONS).to_json,
  "plain/hash" => Oj.dump(RECORD.as_json(PLAIN_AS_JSON_OPTIONS))
}
parsed_outputs = parity_outputs.transform_values { |s| Oj.load(s, mode: :strict) }
reference_label, reference = parsed_outputs.first
parsed_outputs.each do |label, value|
  next if label == reference_label
  next if value == reference
  warn "JSON output mismatch between #{reference_label} and #{label}:"
  warn "  #{reference_label}: #{Oj.dump(reference)}"
  warn "  #{label}: #{Oj.dump(value)}"
  abort "aborting bench — output shapes diverged"
end
puts "JSON output parity verified: #{parity_outputs.keys.join(", ")}"
puts "Sample: #{Oj.dump(reference)}"
puts

# --- Scenario rows --------------------------------------------------------
# Inline target lambdas — the registry exists to share callables across
# scenarios; this file is the only consumer of these lambdas, so threading
# through `Targets::*` would add noise without payoff.

rows = {
  "serializers_code_gen/json" => -> { SCG_JSON_SINGLE.serialize_one(RECORD) },
  "serializers_code_gen/hash" => -> { SCG_HASH_SINGLE.serialize_one(RECORD) },
  "panko/json" => -> { PostPankoSerializer.new.serialize_to_json(RECORD) },
  "panko/object" => -> { PostPankoSerializer.new.serialize(RECORD) },
  "oj_serializers/json" => -> { PostOjJsonSerializer.one(RECORD).to_s },
  "oj_serializers/hash" => -> { PostOjHashSerializer.one(RECORD) },
  "plain/json" => -> { RECORD.as_json(PLAIN_AS_JSON_OPTIONS).to_json },
  "plain/hash" => -> { RECORD.as_json(PLAIN_AS_JSON_OPTIONS) }
}

rows.each do |row_label, row_callable|
  next if BENCHMARK_CONFIG.target && !row_label.downcase.include?(BENCHMARK_CONFIG.target.downcase)
  benchmark("SingleRecord/#{row_label}", &row_callable)
end
