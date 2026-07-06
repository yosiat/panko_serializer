# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "recursive_self"

RSpec.describe "Generated Class for Fixtures::RecursiveSelf" do
  let(:descriptor) { Fixtures::RecursiveSelf::DESCRIPTOR }
  let(:config) { Fixtures::RecursiveSelf::CONFIG }

  describe "#serialize_one — finite Comment tree" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { Panko::CodeGen.compile(descriptor, output: mode, config: config) }
        let(:generated) { generated_class.new(descriptor: descriptor) }

        it "compiles + constructs without infinite recursion (self-recursion shortcut wired)" do
          expect { generated_class.new(descriptor: descriptor) }.not_to raise_error
        end

        it "serializes a finite 3-node Comment tree (root with two leaf replies) per docs/testing.md § recursive_self" do
          root = Comment.create!(body: "root")
          c1 = Comment.create!(body: "c1", parent_comment: root)
          c2 = Comment.create!(body: "c2", parent_comment: root)
          root.reload
          expected = case mode
          when :json
            %({"id":#{root.id},"body":"root","replies":[) +
              %({"id":#{c1.id},"body":"c1","replies":[]},) +
              %({"id":#{c2.id},"body":"c2","replies":[]}]})
          when :hash
            {
              "id" => root.id,
              "body" => "root",
              "replies" => [
                {"id" => c1.id, "body" => "c1", "replies" => []},
                {"id" => c2.id, "body" => "c2", "replies" => []}
              ]
            }
          end
          expect(generated.serialize_one(root)).to eq(expected)
        end

        it "serializes a leaf Comment (no replies) as the empty-collection terminal case" do
          leaf = Comment.create!(body: "leaf")
          expected = case mode
          when :json then %({"id":#{leaf.id},"body":"leaf","replies":[]})
          when :hash then {"id" => leaf.id, "body" => "leaf", "replies" => []}
          end
          expect(generated.serialize_one(leaf)).to eq(expected)
        end
      end
    end
  end

  describe "Self-recursion wiring — @<name>_serializer = self" do
    let(:generated_class) { Panko::CodeGen.compile(descriptor, output: :json, config: config) }
    let(:generated) { generated_class.new(descriptor: descriptor) }

    it "@replies_serializer is the parent serializer instance itself (one Generated Class instance per unique Descriptor)" do
      expect(generated.instance_variable_get(:@replies_serializer)).to equal(generated)
    end

    it "Compile produces one Generated Class per unique Descriptor — the self-reference shares the same class" do
      replies_serializer = generated.instance_variable_get(:@replies_serializer)
      expect(replies_serializer.class).to equal(generated_class)
    end
  end
end
