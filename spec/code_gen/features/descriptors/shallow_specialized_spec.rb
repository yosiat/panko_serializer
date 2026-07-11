# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "shallow_specialized"

RSpec.describe "Generated Class for Fixtures::ShallowSpecialized" do
  let(:descriptor) { Fixtures::ShallowSpecialized::DESCRIPTOR }
  let(:config) { Fixtures::ShallowSpecialized::CONFIG }

  describe "#serialize_one — AR Records via the Specialized path" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { Panko::CodeGen.compile(descriptor, output: mode, config: config) }
        let(:generated) { generated_class.new(descriptor: descriptor) }

        it "honors the user-defined reader override on a column-backed Attribute (method dispatch, not _read_attribute)" do
          post = Post.create!(title: "hello", body: "world", views: 7)
          expect(post.title).to eq("HELLO")
          output = generated.serialize_one(post)
          case mode
          when :json
            expect(output).to include(%("title":"HELLO"))
            expect(output).not_to include(%("title":"hello"))
          when :hash
            expect(output["title"]).to eq("HELLO")
          end
        end

        it "calls the instance method for a method-dispatched Attribute (override on title is honored inside #headline)" do
          post = Post.create!(title: "hi", body: "world", views: 1)
          output = generated.serialize_one(post)
          expected_headline = "HI (id=#{post.id})"
          case mode
          when :json
            expect(output).to include(%("headline":"#{expected_headline}"))
          when :hash
            expect(output["headline"]).to eq(expected_headline)
          end
        end

        it "emits the full expected output for a sanity AR record" do
          post = Post.create!(title: "hi", body: "world", views: 7)
          expected = case mode
          when :json
            %({"id":#{post.id},"title":"HI","headline":"HI (id=#{post.id})","static":42,"contextual":null})
          when :hash
            {
              "id" => post.id,
              "title" => "HI",
              "headline" => "HI (id=#{post.id})",
              "static" => 42,
              "contextual" => nil
            }
          end
          expect(generated.serialize_one(post)).to eq(expected)
        end

        it "invokes a MethodAttribute body of arity 0 with no arguments" do
          post = Post.create!(title: "hi", body: "world", views: 1)
          output = generated.serialize_one(post)
          case mode
          when :json then expect(output).to include(%("static":42))
          when :hash then expect(output["static"]).to eq(42)
          end
        end

        it "omits a MethodAttribute key when the arity-1 body returns SKIP" do
          post = Post.create!(title: "hi", body: "world", views: 1)
          output = generated.serialize_one(post)
          case mode
          when :json then expect(output).not_to include(%("hidden"))
          when :hash then expect(output).not_to have_key("hidden")
          end
        end

        it "threads context through an arity-2 MethodAttribute body" do
          post = Post.create!(title: "hi", body: "world", views: 1)
          output = generated.serialize_one(post, context: "ctx-value")
          case mode
          when :json then expect(output).to include(%("contextual":"ctx-value"))
          when :hash then expect(output["contextual"]).to eq("ctx-value")
          end
        end
      end
    end
  end

  describe "non-AR class in model: falls back to method dispatch" do
    # Inline helpers (rather than +let+s) keep the memoization cap (5) clear
    # — both per-mode contexts already pull +descriptor+ / +config+ /
    # +generated_class+ / +generated+ from the outer scope, leaving no room
    # for a per-test +non_ar_*+ helper. The Struct + Descriptor are cheap
    # enough to construct per-call; readability wins over memoization.
    def non_ar_record_class
      @non_ar_record_class ||= Struct.new(:id, :title)
    end

    def non_ar_descriptor
      @non_ar_descriptor ||= Panko::CodeGen::Descriptor.new(
        name: "NonArShallowSerializer",
        model: non_ar_record_class,
        attributes: [
          Panko::CodeGen::Attribute.new(name: :id, source: :id),
          Panko::CodeGen::Attribute.new(name: :title, source: :title)
        ],
        method_attributes: [],
        associations: []
      )
    end

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { Panko::CodeGen.compile(non_ar_descriptor, output: mode, config: config) }
        let(:generated) { generated_class.new(descriptor: non_ar_descriptor) }

        it "serializes a non-AR Struct Record via method dispatch (no Hash branch, no _read_attribute)" do
          record = non_ar_record_class.new(1, "hello")
          expected = case mode
          when :json then '{"id":1,"title":"hello"}'
          when :hash then {"id" => 1, "title" => "hello"}
          end
          expect(generated.serialize_one(record)).to eq(expected)
        end
      end
    end
  end

  describe ".compile — Specialized path emits a single _write_one / _to_hash without the Hash branch" do
    it "JSON mode: instance methods include _write_one but not _write_one_hash / _write_one_object" do
      generated_class = Panko::CodeGen.compile(descriptor, output: :json, config: config)
      method_names = generated_class.instance_methods(false)
      expect(method_names).to include(:_write_one)
      expect(method_names).not_to include(:_write_one_hash)
      expect(method_names).not_to include(:_write_one_object)
    end

    it "Hash mode: instance methods include _to_hash but not _to_hash_hash / _to_hash_object" do
      generated_class = Panko::CodeGen.compile(descriptor, output: :hash, config: config)
      method_names = generated_class.instance_methods(false)
      expect(method_names).to include(:_to_hash)
      expect(method_names).not_to include(:_to_hash_hash)
      expect(method_names).not_to include(:_to_hash_object)
    end
  end
end
