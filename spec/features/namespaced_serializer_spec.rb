# frozen_string_literal: true

require "spec_helper"

describe "Namespaced serializers" do
  module NamespacedSerializers
    class AuthorSerializer < Panko::Serializer
      attributes :name
    end

    class PostSerializer < Panko::Serializer
      attributes :title

      has_one :author, serializer: AuthorSerializer
    end
  end

  class NamespacedAuthor
    attr_reader :name

    def initialize(name)
      @name = name
    end
  end

  class NamespacedPost
    attr_reader :title, :author

    def initialize(title, author)
      @title = title
      @author = author
    end
  end

  it "serializes through a namespaced serializer" do
    post = NamespacedPost.new(Faker::Lorem.word, NamespacedAuthor.new(Faker::Lorem.word))

    expect(post).to serialized_as(NamespacedSerializers::PostSerializer,
      "title" => post.title,
      "author" => {"name" => post.author.name})
  end
end
