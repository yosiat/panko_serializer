# frozen_string_literal: true

require_relative "benchmark"
require_relative "setup"
require "panko_serializer"

# --- AR datasets ---

DATASETS[:posts] = {data: Post.all.includes(:author).to_a, noun: "posts"}
DATASETS[:authors] = {data: Author.all.includes(:posts).to_a, noun: "authors"}
DATASETS[:aliased_posts] = {data: PostWithAliasModel.all.to_a, noun: "aliased posts"}

# --- Plain Ruby datasets (no AR dependency) ---

class PlainAuthor
  attr_accessor :id, :name
end

class PlainPost
  attr_accessor :id, :body, :title, :created_at, :author_id
  attr_reader :author

  def author=(author)
    @author = author
    @author_id = author.id
  end
end

plain_posts = 2300.times.map do |i|
  author = PlainAuthor.new
  author.id = i
  author.name = "Author #{i}"

  post = PlainPost.new
  post.id = i
  post.body = "something about how password restrictions are evil"
  post.title = "Your bank does not know how to do security"
  post.created_at = Time.now
  post.author = author
  post
end

DATASETS[:plain_posts] = {data: plain_posts, noun: "plain posts"}
