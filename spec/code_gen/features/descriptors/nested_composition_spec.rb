# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "nested_composition"

RSpec.describe "Generated Class for Fixtures::NestedComposition" do
  let(:descriptor) { Fixtures::NestedComposition::DESCRIPTOR }
  let(:config) { Fixtures::NestedComposition::CONFIG }

  describe "#serialize_one — AR Records via the Generic path's _write_one_object" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { Panko::CodeGen.compile(descriptor, output: mode, config: config) }
        let(:generated) { generated_class.new(descriptor: descriptor) }

        it "serializes a Post with an associated Author and Comments as nested object + array" do
          post = Post.create!
          post.create_author!(name: "alice")
          first = post.comments.create!(body: "first")
          second = post.comments.create!(body: "second")
          post.reload
          expected = case mode
          when :json
            %({"id":#{post.id},"author":{"id":#{post.author.id},"name":"alice"},) +
              %("comments":[{"id":#{first.id},"body":"first"},{"id":#{second.id},"body":"second"}]})
          when :hash
            {
              "id" => post.id,
              "author" => {"id" => post.author.id, "name" => "alice"},
              "comments" => [
                {"id" => first.id, "body" => "first"},
                {"id" => second.id, "body" => "second"}
              ]
            }
          end
          expect(generated.serialize_one(post)).to eq(expected)
        end

        it "emits null/nil for the author key when the Source returns nil (default null_for_missing_has_one: true)" do
          post = Post.create!
          expect(post.author).to be_nil
          expected = case mode
          when :json then %({"id":#{post.id},"author":null,"comments":[]})
          when :hash then {"id" => post.id, "author" => nil, "comments" => []}
          end
          expect(generated.serialize_one(post)).to eq(expected)
        end

        it "emits an empty array for has_many :comments when the Source returns an empty collection" do
          post = Post.create!
          post.create_author!(name: "alice")
          post.reload
          expect(post.comments).to be_empty
          expected = case mode
          when :json then %({"id":#{post.id},"author":{"id":#{post.author.id},"name":"alice"},"comments":[]})
          when :hash
            {
              "id" => post.id,
              "author" => {"id" => post.author.id, "name" => "alice"},
              "comments" => []
            }
          end
          expect(generated.serialize_one(post)).to eq(expected)
        end
      end
    end
  end

  describe "Composition wiring" do
    let(:generated_class) { Panko::CodeGen.compile(descriptor, output: :json, config: config) }

    it "hoists @author_serializer once at construction; the same instance is reused across serialize_one calls" do
      generated = generated_class.new(descriptor: descriptor)
      first = generated.instance_variable_get(:@author_serializer)
      generated.serialize_one({"id" => 1, "author" => {"id" => 7, "name" => "alice"}, "comments" => []})
      generated.serialize_one({"id" => 2, "author" => nil, "comments" => []})
      second = generated.instance_variable_get(:@author_serializer)
      expect(first).to equal(second)
    end

    it "hoists @comments_serializer once at construction; the same instance is reused across serialize_one calls" do
      generated = generated_class.new(descriptor: descriptor)
      first = generated.instance_variable_get(:@comments_serializer)
      generated.serialize_one({"id" => 1, "author" => nil, "comments" => [{"id" => 11, "body" => "x"}]})
      generated.serialize_one({"id" => 2, "author" => nil, "comments" => []})
      second = generated.instance_variable_get(:@comments_serializer)
      expect(first).to equal(second)
    end

    it "@author_serializer is an instance of the inner Generated Class" do
      generated = generated_class.new(descriptor: descriptor)
      author_serializer = generated.instance_variable_get(:@author_serializer)
      # Anonymous Generated Class — assert by responding to the inner serialize entry.
      expect(author_serializer).to respond_to(:_write_one)
    end

    it "@comments_serializer is an instance of the inner Generated Class — every iteration is monomorphic" do
      generated = generated_class.new(descriptor: descriptor)
      comments_serializer = generated.instance_variable_get(:@comments_serializer)
      expect(comments_serializer).to respond_to(:_write_one)
    end
  end

  describe "Compiler recursive descent — identity-keyed compile cache" do
    let(:inner) {
      Panko::CodeGen::Descriptor.new(
        name: "InnerSerializer",
        models: nil,
        attributes: [Panko::CodeGen::Attribute.new(name: :id)],
        method_attributes: [],
        associations: []
      )
    }
    let(:diamond) {
      Panko::CodeGen::Descriptor.new(
        name: "DiamondSerializer",
        models: nil,
        attributes: [],
        method_attributes: [],
        associations: [
          Panko::CodeGen::Association.new(name: :first, kind: :has_one, descriptor: inner),
          Panko::CodeGen::Association.new(name: :second, kind: :has_one, descriptor: inner)
        ]
      )
    }

    %i[json hash].each do |mode|
      it "yields one Generated Class per unique nested Descriptor in #{mode} mode (shared inner deduped)" do
        diamond_class = Panko::CodeGen.compile(diamond, output: mode, config: config)
        instance = diamond_class.new(descriptor: diamond)
        first = instance.instance_variable_get(:@first_serializer)
        second = instance.instance_variable_get(:@second_serializer)
        expect(first.class).to equal(second.class)
      end
    end
  end
end
