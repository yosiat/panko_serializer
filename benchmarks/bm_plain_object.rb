# frozen_string_literal: true

require_relative "./benchmarking_support"
require_relative "./app"

class AuthorFastSerializer < Panko::Serializer
  attributes :id, :name
end

class PostFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :created_at
end

class PostFastWithMethodCallSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id, :method_call

  def method_call
    object.id * 2
  end
end

class PostWithHasOneFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id

  has_one :author, serializer: AuthorFastSerializer
end

class AuthorWithHasManyFastSerializer < Panko::Serializer
  attributes :id, :name

  has_many :posts, serializer: PostFastSerializer
end

class Post
  attr_accessor :id, :body, :title, :created_at, :author_id
  attr_reader :author

  def self.create(attrs)
    p = Post.new
    attrs.each do |k, v|
      p.send :"#{k}=", v
    end
    p
  end

  def author=(author)
    @author = author
    @author_id = author.id
  end
end

class Author
  attr_accessor :id, :name

  def self.create(attrs)
    a = Author.new
    attrs.each do |k, v|
      a.send :"#{k}=", v
    end
    a
  end
end

def benchmark_data
  posts = []
  ENV.fetch("ITEMS_COUNT", "2300").to_i.times do |i|
    posts << Post.create(
      id: i,
      body: "something about how password restrictions are evil, and less secure, and with the math to prove it.",
      title: "Your bank is does not know how to do security",
      author: Author.create(id: i, name: "Preston Sego")
    )
  end

  {all: posts, small: posts.first(50)}
end

def benchmark(prefix, serializer, options = {})
  data = benchmark_data
  posts = data[:all]
  posts_50 = data[:small]

  merged_options = options.merge(each_serializer: serializer)

  Benchmark.run("Panko_Plain_#{prefix}_Posts_#{posts.count}") do
    Panko::ArraySerializer.new(posts, merged_options).to_json
  end

  data = benchmark_data
  posts = data[:all]
  posts_50 = data[:small]

  Benchmark.run("Panko_Plain_#{prefix}_Posts_50") do
    Panko::ArraySerializer.new(posts_50, merged_options).to_json
  end
end

benchmark "Simple", PostFastSerializer
benchmark "HasOne", PostWithHasOneFastSerializer
benchmark "SimpleWithMethodCall", PostFastWithMethodCallSerializer
benchmark "Except", PostWithHasOneFastSerializer, except: [:title]
benchmark "Only", PostWithHasOneFastSerializer, only: [:id, :body, :author_id, :author]
