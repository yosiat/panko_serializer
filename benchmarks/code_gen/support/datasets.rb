# frozen_string_literal: true

require_relative "setup"

# Bench-specific AR schema and models. Kept entirely separate from
# spec/support/{schema,models}.rb because specs and benchmarks have different
# data-creation needs (per docs/benchmarks.md § Fixture data): specs want
# inline `create!` per test; benchmarks want a bulk-pre-seeded dataset shared
# across every measurement in a run. The Bench namespace + bench_* table
# names also keep the harness usable from a subprocess that never touches the
# spec models — and from the smoke spec, which spawns a subprocess.

ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :bench_posts, force: true do |t|
    t.string :title
    t.string :body
    t.integer :views
    t.boolean :published
    # Backs the json_column.rb scenario. Sqlite stores it as text; AR
    # serializes / deserializes through the json column type.
    t.json :metadata
  end

  create_table :bench_authors, force: true do |t|
    t.references :bench_post
    t.string :name
  end

  create_table :bench_comments, force: true do |t|
    t.references :bench_post
    t.string :body
  end
end

# Bench AR models — flat accessors only, no reader overrides. Distinct from
# the spec models (whose `Post#title` upcases its result) so the bench
# numbers reflect raw column reads rather than spec-shape distortions.
module Bench
  class Post < ActiveRecord::Base
    self.table_name = "bench_posts"
    has_one :author, class_name: "Bench::Author", foreign_key: :bench_post_id
    has_many :comments, class_name: "Bench::Comment", foreign_key: :bench_post_id
  end

  class Author < ActiveRecord::Base
    self.table_name = "bench_authors"
    belongs_to :post, class_name: "Bench::Post", foreign_key: :bench_post_id, optional: true
  end

  class Comment < ActiveRecord::Base
    self.table_name = "bench_comments"
    belongs_to :post, class_name: "Bench::Post", foreign_key: :bench_post_id, optional: true
  end
end

# Force AR attribute-method codegen up front so the first measured serialize
# call doesn't pay first-call codegen cost (mirrors docs/research/ar_access_bench.rb).
Bench::Post.define_attribute_methods
Bench::Author.define_attribute_methods
Bench::Comment.define_attribute_methods

# Default sizes — matches Panko's current bench (per docs/benchmarks.md §
# Fixture data) so scale numbers stay comparable with existing Panko runs.
BENCHMARK_SIZES = [50, 2300].freeze

# Each bench post receives this many comments — enough rows that the
# has_many.rb scenario exercises a non-trivial inner loop, few enough that
# size=2300 stays under a million inserts at seed time.
COMMENTS_PER_POST = 5

# Pre-seed the largest required size; benchmark_with_records / benchmark_scenario
# slice to the specific size each iteration requested.
max_size = BENCHMARK_SIZES.max
post_attrs = Array.new(max_size) do |i|
  {
    title: "Post ##{i}",
    body: "Body of post ##{i}, with some content to serialize across the wire.",
    views: i,
    published: i.even?,
    metadata: {"category" => "tech", "tags" => %w[ruby json benchmark], "featured" => i % 7 == 0}
  }
end
Bench::Post.insert_all(post_attrs)

post_ids = Bench::Post.pluck(:id)

author_attrs = post_ids.each_with_index.map do |post_id, i|
  {bench_post_id: post_id, name: "Author ##{i}"}
end
Bench::Author.insert_all(author_attrs)

comment_attrs = post_ids.flat_map do |post_id|
  Array.new(COMMENTS_PER_POST) do |j|
    {bench_post_id: post_id, body: "Comment ##{j} on post #{post_id}"}
  end
end
Bench::Comment.insert_all(comment_attrs)

# Registry mapping `type:` symbols → pre-seeded record arrays. Scenario files
# pass a `type:` to benchmark_with_records / benchmark_scenario; the harness
# slices to the requested size. Posts are eager-loaded with author + comments
# so association-walking scenarios don't pay an N+1 query cost inside the
# measured block.
DATASETS = {
  posts: Bench::Post.includes(:author, :comments).to_a,
  authors: Bench::Author.includes(:post).to_a,
  comments: Bench::Comment.includes(:post).to_a
}.freeze
