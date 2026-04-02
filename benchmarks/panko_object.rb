# frozen_string_literal: true

require_relative "support/datasets"

class AuthorFastSerializer < Panko::Serializer
  attributes :id, :name
end

class PostFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :created_at
end

class PostWithHasOneFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :created_at

  has_one :author, serializer: AuthorFastSerializer
end

class PostWithAliasFastSerializer < Panko::Serializer
  attributes :new_id, :new_body, :new_title, :new_author_id, :new_created_at
end

benchmark_with_records("Simple", type: :posts) { |r| Panko::ArraySerializer.new(r, each_serializer: PostFastSerializer).to_a }
benchmark_with_records("HasOne", type: :posts) { |r| Panko::ArraySerializer.new(r, each_serializer: PostWithHasOneFastSerializer).to_a }
benchmark_with_records("Except", type: :posts) { |r| Panko::ArraySerializer.new(r, each_serializer: PostWithHasOneFastSerializer, except: [:title]).to_a }
benchmark_with_records("Only", type: :posts) { |r| Panko::ArraySerializer.new(r, each_serializer: PostWithHasOneFastSerializer, only: [:id, :body, :author_id, :author]).to_a }
benchmark_with_records("Aliases", type: :aliased_posts) { |r| Panko::ArraySerializer.new(r, each_serializer: PostWithAliasFastSerializer).to_a }
