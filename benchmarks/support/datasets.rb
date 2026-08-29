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

# Wide-attribute column count for the wide_attributes.rb scenario — a
# count in the 60-80 range that gives meaningful per-Field measurement
# beyond what Panko's existing bench covers (per docs/benchmarks.md §
# Open refinements). 70 splits cleanly across the four AR-visible primitive
# types we want to stress: 30 strings, 20 integers, 10 booleans, 5
# decimals, 5 dates.
WIDE_POST_STRING_COUNT = 30
WIDE_POST_INTEGER_COUNT = 20
WIDE_POST_BOOLEAN_COUNT = 10
WIDE_POST_DECIMAL_COUNT = 5
WIDE_POST_DATE_COUNT = 5

WIDE_POST_STRING_NAMES = (1..WIDE_POST_STRING_COUNT).map { |i| "s_%02d" % i }.freeze
WIDE_POST_INTEGER_NAMES = (1..WIDE_POST_INTEGER_COUNT).map { |i| "i_%02d" % i }.freeze
WIDE_POST_BOOLEAN_NAMES = (1..WIDE_POST_BOOLEAN_COUNT).map { |i| "b_%02d" % i }.freeze
WIDE_POST_DECIMAL_NAMES = (1..WIDE_POST_DECIMAL_COUNT).map { |i| "d_%02d" % i }.freeze
WIDE_POST_DATE_NAMES = (1..WIDE_POST_DATE_COUNT).map { |i| "t_%02d" % i }.freeze
WIDE_POST_ATTRIBUTE_NAMES = (
  WIDE_POST_STRING_NAMES + WIDE_POST_INTEGER_NAMES + WIDE_POST_BOOLEAN_NAMES +
    WIDE_POST_DECIMAL_NAMES + WIDE_POST_DATE_NAMES
).freeze

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
    # Backs the medium_graph_shallow_only.rb scenario's 3-attr Author
    # Descriptor (id, name, email) — matches S13 fixture #6.4's
    # `GRAPH_AUTHOR_DESCRIPTOR` shape verbatim so the with-only IPS row
    # reproduces the `indexed × single_path` verdict cell for rule-2
    # numeric application. Existing scenarios that load `:posts` and walk
    # `Bench::Author` (graph.rb, has_one.rb) don't reference :email and
    # are unaffected by the additional column.
    t.string :email
  end

  create_table :bench_comments, force: true do |t|
    t.references :bench_post
    # Backs the code_gen_recursive.rb scenario's 3-level Comment tree. Nullable
    # so the per-post comments seeded for has_many.rb keep parent_comment_id
    # = nil; only the bench_post_id-less tree comments use it.
    t.references :parent_comment
    t.string :body
  end

  # Backs the wide_attributes.rb scenario — a single table carrying ~70
  # columns split across the four primitive types AR exposes (string /
  # integer / boolean / decimal / date) so per-Field emit/dispatch cost
  # gets measured against a realistic mix rather than 70 columns of one
  # type. The exact count is open per docs/benchmarks.md § Open
  # refinements; tune via the WIDE_POST_*_COUNT constants above.
  create_table :bench_wide_posts, force: true do |t|
    WIDE_POST_STRING_NAMES.each { |n| t.string n }
    WIDE_POST_INTEGER_NAMES.each { |n| t.integer n }
    WIDE_POST_BOOLEAN_NAMES.each { |n| t.boolean n }
    WIDE_POST_DECIMAL_NAMES.each { |n| t.decimal n, precision: 12, scale: 2 }
    WIDE_POST_DATE_NAMES.each { |n| t.date n }
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
    # parent_comment / replies back the code_gen_recursive.rb 3-level comment-tree
    # dataset; both are unused by the has_many.rb per-post comments, where
    # parent_comment_id stays nil.
    belongs_to :parent_comment, class_name: "Bench::Comment", foreign_key: :parent_comment_id, optional: true
    has_many :replies, class_name: "Bench::Comment", foreign_key: :parent_comment_id
  end

  class WidePost < ActiveRecord::Base
    self.table_name = "bench_wide_posts"
  end

  # Stand-in for the user serializer class a Panko-built Descriptor always
  # carries as its +parent_class+; the benchmark Descriptors subclass it so
  # they match the Generated Class shape Panko emits in production.
  class BaseSerializer
  end
end

# Force AR attribute-method codegen up front so the first measured serialize
# call doesn't pay first-call codegen cost (mirrors docs/research/ar_access_bench.rb).
Bench::Post.define_attribute_methods
Bench::Author.define_attribute_methods
Bench::Comment.define_attribute_methods
Bench::WidePost.define_attribute_methods

# Default sizes — matches Panko's current bench (per docs/benchmarks.md §
# Fixture data) so scale numbers stay comparable with existing Panko runs.
BENCHMARK_SIZES = [50, 2300].freeze

# Each bench post receives this many comments — enough rows that the
# has_many.rb scenario exercises a non-trivial inner loop, few enough that
# size=2300 stays under a million inserts at seed time.
COMMENTS_PER_POST = 5

# Pre-seed the largest required size; benchmark_scenario
# slices to the specific size each iteration requested.
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
  {bench_post_id: post_id, name: "Author ##{i}", email: "author#{i}@example.com"}
end
Bench::Author.insert_all(author_attrs)

comment_attrs = post_ids.flat_map do |post_id|
  Array.new(COMMENTS_PER_POST) do |j|
    {bench_post_id: post_id, body: "Comment ##{j} on post #{post_id}"}
  end
end
Bench::Comment.insert_all(comment_attrs)

# 3-level Comment tree backing the code_gen_recursive.rb scenario. Each tree has
# 1 root + COMMENT_TREE_CHILDREN_PER_NODE children, each child carrying its
# own COMMENT_TREE_CHILDREN_PER_NODE grandchildren = 1 + 2 + 4 = 7 nodes per
# tree. Tree comments live in the same bench_comments table but with
# bench_post_id NULL so the per-post comments eager-loaded through the :posts
# dataset stay unaffected.
COMMENT_TREE_CHILDREN_PER_NODE = 2

# Per-level placeholder counts at max_size=2300 (≤2 fields per row) stay
# well under sqlite's default SQLITE_MAX_VARIABLE_NUMBER (32766 on modern
# sqlite), so each level fits in a single insert_all without batching —
# same window the per-post comment insert already trusts.
tree_root_attrs = Array.new(max_size) do |i|
  {body: "Tree root ##{i}"}
end
Bench::Comment.insert_all(tree_root_attrs)
tree_root_ids = Bench::Comment.where(bench_post_id: nil, parent_comment_id: nil).order(:id).pluck(:id)

tree_child_attrs = tree_root_ids.flat_map do |root_id|
  Array.new(COMMENT_TREE_CHILDREN_PER_NODE) do |j|
    {parent_comment_id: root_id, body: "Tree child ##{j} of root #{root_id}"}
  end
end
Bench::Comment.insert_all(tree_child_attrs) unless tree_child_attrs.empty?
tree_child_ids = Bench::Comment.where(bench_post_id: nil).where.not(parent_comment_id: nil).order(:id).pluck(:id)

tree_grandchild_attrs = tree_child_ids.flat_map do |child_id|
  Array.new(COMMENT_TREE_CHILDREN_PER_NODE) do |j|
    {parent_comment_id: child_id, body: "Tree grandchild ##{j} of child #{child_id}"}
  end
end
Bench::Comment.insert_all(tree_grandchild_attrs) unless tree_grandchild_attrs.empty?

# Wide-post seeding — generate one row per slot with deterministic varied
# values across the four primitive types. Insert in batches so the
# 2300 × 70 = 161 000-placeholder shape stays under sqlite's variable cap
# (32766 on modern sqlite); 400 × 70 = 28 000 placeholders per batch.
WIDE_POST_INSERT_BATCH = 400
base_date = Date.new(2025, 1, 1)
wide_attrs = Array.new(max_size) do |i|
  row = {}
  WIDE_POST_STRING_NAMES.each_with_index { |n, j| row[n] = "s#{j}_v#{i}" }
  WIDE_POST_INTEGER_NAMES.each_with_index { |n, j| row[n] = i + j }
  WIDE_POST_BOOLEAN_NAMES.each_with_index { |n, j| row[n] = (i + j).even? }
  # Decimals as formatted strings — insert_all bypasses AR type-casting,
  # SQLite stores TEXT/REAL transparently, and the read-side cast back to
  # BigDecimal happens at attribute access time inside the measured block
  # (which is what we want to measure for the wide-attribute scenario).
  WIDE_POST_DECIMAL_NAMES.each_with_index { |n, j| row[n] = "%.2f" % ((i * 100 + j) / 100.0) }
  WIDE_POST_DATE_NAMES.each_with_index { |n, j| row[n] = base_date + (i + j) }
  row
end
wide_attrs.each_slice(WIDE_POST_INSERT_BATCH) { |slice| Bench::WidePost.insert_all(slice) }

# Registry mapping `type:` symbols → pre-seeded record arrays. Scenario files
# pass a `type:` to benchmark_scenario; the harness
# slices to the requested size. Posts are eager-loaded with author + comments
# so association-walking scenarios don't pay an N+1 query cost inside the
# measured block. :comment_trees returns only the roots; eager-loading nests three
# levels (replies → replies → replies) so even the leaf grandchildren have
# their (empty) replies cache populated — without the third level, the
# recursive serializer would issue one SELECT per grandchild inside the
# measured block.
DATASETS = {
  posts: Bench::Post.includes(:author, :comments).to_a,
  comment_trees: Bench::Comment.where(bench_post_id: nil, parent_comment_id: nil).includes(replies: {replies: :replies}).to_a,
  wide_posts: Bench::WidePost.all.to_a
}.freeze
