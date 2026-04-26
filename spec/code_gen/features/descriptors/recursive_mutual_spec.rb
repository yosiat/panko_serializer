# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"
require "recursive_mutual"

RSpec.describe "Generated Class for Fixtures::RecursiveMutual" do
  let(:descriptor) { Fixtures::RecursiveMutual::DESCRIPTOR }
  let(:config) { Fixtures::RecursiveMutual::CONFIG }

  describe "#serialize_one — finite Folder/Item cycle" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { SerializersCodeGen.compile(descriptor, output: mode, config: config) }
        let(:generated) { generated_class.new(descriptor: descriptor) }

        it "compiles + constructs without infinite recursion (mutual-cycle construct cache wired)" do
          expect { generated_class.new(descriptor: descriptor) }.not_to raise_error
        end

        it "serializes a Folder → Item → Folder chain (2-deep, inner Folder with no items) per docs/testing.md § recursive_mutual" do
          inner = Folder.create!(name: "inner")
          root = Folder.create!(name: "root")
          item = Item.create!(name: "item-1", folder: root, subfolder: inner)
          root.reload
          expected = case mode
          when :json
            %({"id":#{root.id},"name":"root","items":[) +
              %({"id":#{item.id},"name":"item-1","subfolder":) +
              %({"id":#{inner.id},"name":"inner","items":[]}}]})
          when :hash
            {
              "id" => root.id,
              "name" => "root",
              "items" => [
                {
                  "id" => item.id,
                  "name" => "item-1",
                  "subfolder" => {"id" => inner.id, "name" => "inner", "items" => []}
                }
              ]
            }
          end
          expect(generated.serialize_one(root)).to eq(expected)
        end

        it "serializes an empty Folder (no items) as the empty-collection terminal case" do
          empty = Folder.create!(name: "empty")
          expected = case mode
          when :json then %({"id":#{empty.id},"name":"empty","items":[]})
          when :hash then {"id" => empty.id, "name" => "empty", "items" => []}
          end
          expect(generated.serialize_one(empty)).to eq(expected)
        end
      end
    end
  end

  describe "Mutual-recursion wiring — one Generated Class instance per unique Descriptor" do
    let(:generated_class) { SerializersCodeGen.compile(descriptor, output: :json, config: config) }
    let(:generated) { generated_class.new(descriptor: descriptor) }

    it "the chain Folder@items_serializer.@subfolder_serializer collapses back to the outer Folder instance" do
      inner_serializer = generated.instance_variable_get(:@items_serializer)
      back_to_outer = inner_serializer.instance_variable_get(:@subfolder_serializer)
      expect(back_to_outer).to equal(generated)
    end

    it "Compile produces one Generated Class per unique Descriptor — Folder traversed twice in the cycle resolves to one class" do
      item_serializer = generated.instance_variable_get(:@items_serializer)
      folder_via_cycle = item_serializer.instance_variable_get(:@subfolder_serializer)
      expect(folder_via_cycle.class).to equal(generated_class)
    end

    it "the inner Item Generated Class is shared across the cycle (one instance, threaded via _construct_cache)" do
      item_serializer = generated.instance_variable_get(:@items_serializer)
      back_to_outer = item_serializer.instance_variable_get(:@subfolder_serializer)
      item_via_cycle = back_to_outer.instance_variable_get(:@items_serializer)
      expect(item_via_cycle).to equal(item_serializer)
    end

    it "two separate constructions of the same Descriptor produce independent instance graphs (each Compile call's cache is per-call)" do
      a = generated_class.new(descriptor: descriptor)
      b = generated_class.new(descriptor: descriptor)
      expect(a).not_to equal(b)
      expect(a.instance_variable_get(:@items_serializer)).not_to equal(b.instance_variable_get(:@items_serializer))
    end
  end

  describe "Acyclic-construction contract — _construct_cache: kwarg is internal" do
    let(:generated_class) { SerializersCodeGen.compile(descriptor, output: :json, config: config) }

    it "constructs without the caller passing _construct_cache: (default {} kicks off a fresh cycle-walk)" do
      expect { generated_class.new(descriptor: descriptor) }.not_to raise_error
    end
  end
end
