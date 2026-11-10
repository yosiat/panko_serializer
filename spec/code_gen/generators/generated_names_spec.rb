# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

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

  describe "instance variable names" do
    it "derives each ivar from the Field's position, not its name" do
      expect(described_class.serializer_ivar(1)).to eq("@child_1")
      expect(described_class.variant_serializer_ivar(1, 0)).to eq("@child_1_0")
      expect(described_class.callable_ivar(2)).to eq("@cb_2")
      expect(described_class.if_guard_ivar(1)).to eq("@cb_if_1")
    end
  end

  describe "literals" do
    let(:names) { [:"2faEnabled", :'a"b', :"\#{raise}", :"user-name", :id] }

    it "writes a String literal that evaluates back to the name" do
      names.each { |name| expect(eval(described_class.string_literal(name))).to eq(name.to_s) } # rubocop:disable Security/Eval
    end

    it "writes a Symbol literal that evaluates back to the name" do
      names.each { |name| expect(eval(described_class.symbol_literal(name))).to eq(name) } # rubocop:disable Security/Eval
    end
  end

  describe ".method_call" do
    it "uses dot syntax for a name Ruby can parse after a dot" do
      expect(described_class.method_call("record", :admin?)).to eq("record.admin?")
    end

    it "uses __send__ for any other name" do
      expect(described_class.method_call("record", :"2fa")).to eq(%(record.__send__(:"2fa")))
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
