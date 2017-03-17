require_relative './benchmarking_support'
require_relative './app'
require_relative './setup'

module Native
  ATTR_id = "id".freeze
  ATTR_body = "body".freeze
  ATTR_title = "title".freeze
  ATTR_author_id = "author_id".freeze
  ATTR_name = "name".freeze
  ATTR_author = "author".freeze

  def self.serialize posts
    posts.map do |post|
      obj = {}

      obj[ATTR_id] = post.id
      obj[ATTR_body] = post.body
      obj[ATTR_title] = post.title
      obj[ATTR_author_id] = post.author_id

      obj[ATTR_author] = {}
      obj[ATTR_author][ATTR_id] = post.author.id
      obj[ATTR_author][ATTR_name] = post.author.name

      obj
    end
  end

end

posts = Post.all.to_a
posts_50 = posts.first(50).to_a

Benchmark.ams("Native_HasOne_Posts_#{posts.count}") do
  Native::serialize posts
end

Benchmark.ams("Native_HasOne_Posts_50") do
  Native::serialize posts_50
end

