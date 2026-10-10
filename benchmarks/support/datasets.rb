# frozen_string_literal: true

require_relative "setup"

ActiveRecord::Migration.verbose = false

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
    t.json :metadata
  end

  create_table :bench_authors, force: true do |t|
    t.references :bench_post
    t.string :name
    t.string :email
  end

  create_table :bench_comments, force: true do |t|
    t.references :bench_post
    t.references :parent_comment
    t.string :body
  end

  create_table :bench_wide_posts, force: true do |t|
    WIDE_POST_STRING_NAMES.each { |n| t.string n }
    WIDE_POST_INTEGER_NAMES.each { |n| t.integer n }
    WIDE_POST_BOOLEAN_NAMES.each { |n| t.boolean n }
    WIDE_POST_DECIMAL_NAMES.each { |n| t.decimal n, precision: 12, scale: 2 }
    WIDE_POST_DATE_NAMES.each { |n| t.date n }
  end
end

# No reader overrides, so the numbers measure plain column reads.
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
    belongs_to :parent_comment, class_name: "Bench::Comment", foreign_key: :parent_comment_id, optional: true
    has_many :replies, class_name: "Bench::Comment", foreign_key: :parent_comment_id
  end

  class WidePost < ActiveRecord::Base
    self.table_name = "bench_wide_posts"
  end

  # Stands in for the user serializer class that a Panko-built Descriptor has as its parent_class.
  class BaseSerializer
  end
end

Bench::Post.define_attribute_methods
Bench::Author.define_attribute_methods
Bench::Comment.define_attribute_methods
Bench::WidePost.define_attribute_methods

BENCHMARK_SIZES = [50, 2300].freeze

COMMENTS_PER_POST = 5

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

# Comment trees have no bench_post_id, so they stay out of the comments loaded with :posts.
COMMENT_TREE_CHILDREN_PER_NODE = 2

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

WIDE_POST_INSERT_BATCH = 400
base_date = Date.new(2025, 1, 1)
wide_attrs = Array.new(max_size) do |i|
  row = {}
  WIDE_POST_STRING_NAMES.each_with_index { |n, j| row[n] = "s#{j}_v#{i}" }
  WIDE_POST_INTEGER_NAMES.each_with_index { |n, j| row[n] = i + j }
  WIDE_POST_BOOLEAN_NAMES.each_with_index { |n, j| row[n] = (i + j).even? }
  WIDE_POST_DECIMAL_NAMES.each_with_index { |n, j| row[n] = "%.2f" % ((i * 100 + j) / 100.0) }
  WIDE_POST_DATE_NAMES.each_with_index { |n, j| row[n] = base_date + (i + j) }
  row
end
wide_attrs.each_slice(WIDE_POST_INSERT_BATCH) { |slice| Bench::WidePost.insert_all(slice) }

# Eager-loaded so no query runs inside the measured block. Comment trees load a third
# replies level so the grandchildren's empty replies are loaded too.
DATASETS = {
  posts: Bench::Post.includes(:author, :comments).to_a,
  comment_trees: Bench::Comment.where(bench_post_id: nil, parent_comment_id: nil).includes(replies: {replies: :replies}).to_a,
  wide_posts: Bench::WidePost.all.to_a
}.freeze
