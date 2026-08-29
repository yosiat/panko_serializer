# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

# Pins the emitted-symbol vocabulary: every name that generated source and
# its emitters must agree on — ivar tokens, write-method names, the
# FIELD_INDEX constant, the writer-pool storage key, and the filter-key
# rule (name for value Fields, Source for Associations). These literals ARE
# the contract; emitters and emit-specs consume this module instead of
# restating them.
RSpec.describe Panko::CodeGen::Generators::GeneratedNames do
  let(:leaf) do
    Panko::CodeGen::Descriptor.new(
      name: "GeneratedNamesLeafSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )
  end

  let(:descriptor) do
    Panko::CodeGen::Descriptor.new(
      name: "GeneratedNamesPostSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )
  end

  let(:attribute) { Panko::CodeGen::Attribute.new(name: :headline, source: :title) }
  let(:method_attribute) { Panko::CodeGen::MethodAttribute.new(name: :slug, body: ->(record) { record["title"] }) }
  let(:association) { Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: leaf) }
  let(:aliased_association) do
    Panko::CodeGen::Association.new(name: :history, kind: :has_many, descriptor: leaf, source: :comments)
  end

  describe ".class_name" do
    it "joins the Descriptor name and the mode suffix" do
      expect(described_class.class_name(descriptor, "JSON")).to eq("GeneratedNamesPostSerializer_JSON")
      expect(described_class.class_name(descriptor, "Hash")).to eq("GeneratedNamesPostSerializer_Hash")
    end
  end

  describe ".serializer_ivar" do
    it "derives the Composition ivar from the association's declared name" do
      expect(described_class.serializer_ivar(association)).to eq("@author_serializer")
      expect(described_class.serializer_ivar(aliased_association)).to eq("@history_serializer")
    end
  end

  describe ".callable_ivar" do
    it "derives the hoisted-Callable ivar from the method attribute's name" do
      expect(described_class.callable_ivar(method_attribute)).to eq("@cb_slug")
    end
  end

  describe ".if_guard_ivar" do
    it "derives the if-guard ivar from the association's declared name" do
      expect(described_class.if_guard_ivar(association)).to eq("@cb_if_author")
    end
  end

  describe "write-method names" do
    it "pins the per-mode entry points and their guarded generic twins" do
      expect(described_class.write_one).to eq("_write_one")
      expect(described_class.to_hash).to eq("_to_hash")
      expect(described_class.generic_write_one).to eq("_generic_write_one")
      expect(described_class.generic_to_hash).to eq("_generic_to_hash")
    end

    it "pins the above-threshold per-shape helper names" do
      expect(described_class.write_one_hash).to eq("_write_one_hash")
      expect(described_class.write_one_object).to eq("_write_one_object")
      expect(described_class.to_hash_hash).to eq("_to_hash_hash")
      expect(described_class.to_hash_object).to eq("_to_hash_object")
    end
  end

  describe ".field_index_const" do
    it "pins the per-class filter-index constant name" do
      expect(described_class.field_index_const).to eq("FIELD_INDEX")
    end
  end

  describe ".writer_pool_key" do
    it "derives the fiber-local storage Symbol from the JSON class name" do
      expect(described_class.writer_pool_key(descriptor)).to eq(:_panko_writer__GeneratedNamesPostSerializer_JSON)
    end
  end

  describe ".filter_key" do
    it "keys value Fields by their output name" do
      expect(described_class.filter_key(attribute)).to eq(:headline)
      expect(described_class.filter_key(method_attribute)).to eq(:slug)
    end

    it "keys Associations by their declared Source, not their output name" do
      expect(described_class.filter_key(association)).to eq(:author)
      expect(described_class.filter_key(aliased_association)).to eq(:comments)
    end
  end
end
