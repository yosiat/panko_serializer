# frozen_string_literal: true

require_relative "support/benchmark"

# Method attributes that memoize a per-call value in an instance variable. The pooled
# instance must drop the memo at checkin, so each call below recomputes it once.

class MemoAuthorPankoSerializer < Panko::Serializer
  attributes :id, :name, :tagged_name

  def tagged_name
    "#{tag} #{object.name}"
  end

  def tag
    @tag ||= context.fetch(:tag).upcase
  end
end

class MemoCommentPankoSerializer < Panko::Serializer
  attributes :id, :body, :tagged_body

  def tagged_body
    "#{tag} #{object.body}"
  end

  def tag
    @tag ||= context.fetch(:tag).upcase
  end
end

class MemoPostPankoSerializer < Panko::Serializer
  attributes :id, :title, :tagged_title
  has_one :author, serializer: MemoAuthorPankoSerializer
  has_many :comments, serializer: MemoCommentPankoSerializer

  def tagged_title
    "#{tag} #{object.title}"
  end

  def tag
    @tag ||= context.fetch(:tag).upcase
  end
end

MEMO_CONTEXT = {tag: "post"}.freeze
MEMO_RECORD = DATASETS.fetch(:posts).first

benchmark("MemoizedMethodAttribute single/panko/object") do
  MemoPostPankoSerializer.new(context: MEMO_CONTEXT).serialize(MEMO_RECORD)
end

benchmark("MemoizedMethodAttribute single/panko/json") do
  MemoPostPankoSerializer.new(context: MEMO_CONTEXT).serialize_to_json(MEMO_RECORD)
end

benchmark_scenario "MemoizedMethodAttribute", type: :posts do |records|
  {
    "panko/json" => -> { Panko::ArraySerializer.new(records, each_serializer: MemoPostPankoSerializer, context: MEMO_CONTEXT).to_json },
    "panko/object" => -> { Panko::ArraySerializer.new(records, each_serializer: MemoPostPankoSerializer, context: MEMO_CONTEXT).to_a }
  }
end
