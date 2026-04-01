# frozen_string_literal: true

require_relative "support/benchmark"
require_relative "support/setup"
require "panko_serializer"

# --- Filters.apply ---

def generate_attributes(count)
  (1..count).map { |i| :"attr_#{i}" }
end

class FLeafSerializer < Panko::Serializer
  attributes(*generate_attributes(5))
end

class FChildSerializer < Panko::Serializer
  attributes(*generate_attributes(15))
  has_one :leaf, serializer: FLeafSerializer
end

class FParentSerializer < Panko::Serializer
  attributes(*generate_attributes(30))
  has_many :children, serializer: FChildSerializer
end

base_descriptor = Panko::SerializationDescriptor.build(FParentSerializer)
only_array = generate_attributes(10)
only_hash = {
  instance: generate_attributes(10) + [:children],
  children: generate_attributes(7) + [:leaf],
  leaf: generate_attributes(3)
}

benchmark("Filters no-op") do
  descriptor = Panko::SerializationDescriptor.duplicate(base_descriptor)
  Panko::Filters.apply(descriptor, {})
end

benchmark("Filters :only array") do
  descriptor = Panko::SerializationDescriptor.duplicate(base_descriptor)
  Panko::Filters.apply(descriptor, only: only_array)
end

benchmark("Filters :only hash (nested)") do
  descriptor = Panko::SerializationDescriptor.duplicate(base_descriptor)
  Panko::Filters.apply(descriptor, only: only_hash)
end

# --- RecordState#setup ---

RS = Panko::Engine::AttributesWriter::ActiveRecord::RecordState

class PostBenchSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :created_at
end

posts = Post.all.to_a
first_post = posts.first

benchmark("RecordState fast path (same batch)") do
  rs = RS.new
  rs.setup(first_post)
  rs.setup(first_post)
end

benchmark("RecordState full path (same class)") do
  rs = RS.new
  rs.setup(first_post)
  rs.setup(posts[1])
end

benchmark("RecordState class change") do
  rs = RS.new
  rs.setup(first_post)
  rs.setup(Author.first)
end

# --- SerializationDescriptor.build ---

benchmark("Descriptor no filters") do
  Panko::SerializationDescriptor.build(FParentSerializer)
end

benchmark("Descriptor attribute filter") do
  Panko::SerializationDescriptor.build(FParentSerializer, only: [:children])
end

benchmark("Descriptor association filters") do
  Panko::SerializationDescriptor.build(FParentSerializer, only: only_hash)
end
