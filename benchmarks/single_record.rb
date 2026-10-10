# frozen_string_literal: true

require_relative "support/benchmark"

RECORD = DATASETS.fetch(:posts).first

SINGLE_AUTHOR_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "SingleRecordAuthorBenchSerializer",
  model: Bench::Author,
  parent_class: Bench::BaseSerializer,
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
  parent_class: Bench::BaseSerializer,
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
    Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: SINGLE_AUTHOR_DESCRIPTOR),
    Panko::CodeGen::Association.new(name: :comments, kind: :has_many, descriptor: SINGLE_COMMENT_DESCRIPTOR)
  ]
)

CODE_GEN_JSON_SINGLE = Panko::CodeGen.compile(SINGLE_POST_DESCRIPTOR, output: :json).new(descriptor: SINGLE_POST_DESCRIPTOR)
CODE_GEN_HASH_SINGLE = Panko::CodeGen.compile(SINGLE_POST_DESCRIPTOR, output: :hash).new(descriptor: SINGLE_POST_DESCRIPTOR)

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

# Separate classes so each row can call `.one`: default_format picks per class whether `.one` returns JSON or a Hash.

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

# as_json returns every column by default; limit it to the serializer fields so the parity check can pass.
PLAIN_AS_JSON_OPTIONS = {
  only: [:id, :title, :body, :views, :published],
  include: {
    author: {only: [:id, :name]},
    comments: {only: [:id, :body]}
  }
}.freeze

# Hash rows are dumped to JSON only for this check; the timed rows below return the Hash itself.
parity_outputs = {
  "code_gen/json" => CODE_GEN_JSON_SINGLE.serialize_one(RECORD),
  "code_gen/hash" => Oj.dump(CODE_GEN_HASH_SINGLE.serialize_one(RECORD)),
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

rows = {
  "code_gen/json" => -> { CODE_GEN_JSON_SINGLE.serialize_one(RECORD) },
  "code_gen/hash" => -> { CODE_GEN_HASH_SINGLE.serialize_one(RECORD) },
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
