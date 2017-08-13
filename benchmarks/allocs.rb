
# frozen_string_literal: true
require_relative "./benchmarking_support"
require_relative "./app"
require_relative "./setup"

require "memory_profiler"

class PostFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id
end

def count_allocs(&block)
  memory_report = MemoryProfiler.report(&block)
  puts memory_report.pretty_print
end

posts = Post.all.to_a
merged_options = {}.merge(each_serializer: PostFastSerializer)
posts_array_serializer = Panko::ArraySerializer.new([], merged_options)

# prints out 18402
count_allocs { posts_array_serializer.serialize_to_json posts }
