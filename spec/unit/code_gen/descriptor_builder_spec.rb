# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "panko/code_gen/descriptor_builder"

class DescriptorBuilderInnerSerializer < Panko::Serializer
  attributes :id
end

class DescriptorBuilderAttributesSerializer < Panko::Serializer
  attributes :id, :name
end

class DescriptorBuilderAliasSerializer < Panko::Serializer
  aliases({created_at: :createdAt})
end

class DescriptorBuilderMethodSerializer < Panko::Serializer
  attributes :greeting

  def greeting
    "hi"
  end
end

class DescriptorBuilderHasOneSerializer < Panko::Serializer
  attributes :id
  has_one :author, serializer: DescriptorBuilderInnerSerializer
end

class DescriptorBuilderRenamedHasOneSerializer < Panko::Serializer
  attributes :id
  has_one :owner, name: :user, serializer: DescriptorBuilderInnerSerializer
end

class DescriptorBuilderHasManySerializer < Panko::Serializer
  attributes :id
  has_many :comments, serializer: DescriptorBuilderInnerSerializer
end

class DescriptorBuilderRecursiveSerializer < Panko::Serializer
  attributes :id
  has_many :replies, serializer: DescriptorBuilderRecursiveSerializer
end

describe Panko::CodeGen::DescriptorBuilder do
  def build(serializer)
    described_class.from_panko_descriptor(serializer._descriptor)
  end

  def cg_attr(name, source = name)
    Panko::CodeGen::Attribute.new(name: name, source: source)
  end

  def cg_method(name, body)
    Panko::CodeGen::MethodAttribute.new(name: name, body: body)
  end

  describe "attributes" do
    subject(:descriptor) { build(DescriptorBuilderAttributesSerializer) }

    it "maps each attribute with source equal to name" do
      expect(descriptor.attributes).to eq([
        cg_attr(:id),
        cg_attr(:name)
      ])
    end

    it "names the descriptor after the serializer class" do
      expect(descriptor.name).to eq("DescriptorBuilderAttributesSerializer")
    end

    it "targets the generic path" do
      expect(descriptor.models).to be_nil
    end

    it "sets parent_class to the serializer" do
      expect(descriptor.parent_class).to eq(DescriptorBuilderAttributesSerializer)
    end
  end

  describe "aliased attributes" do
    it "maps the alias to the output name and the column to source" do
      expect(build(DescriptorBuilderAliasSerializer).attributes).to eq([
        cg_attr(:createdAt, :created_at)
      ])
    end
  end

  describe "method fields" do
    subject(:descriptor) { build(DescriptorBuilderMethodSerializer) }

    it "maps to a Symbol-body method attribute dispatched on the parent class" do
      expect(descriptor.method_attributes).to eq([
        cg_method(:greeting, :greeting)
      ])
      expect(descriptor.parent_class).to eq(DescriptorBuilderMethodSerializer)
    end

    it "keeps method fields out of the plain-attribute list" do
      expect(descriptor.attributes).to be_empty
    end
  end

  describe "has_one association" do
    subject(:association) { build(DescriptorBuilderHasOneSerializer).associations.first }

    it "reads via the positional and outputs under the same key" do
      expect(association.kind).to eq(:has_one)
      expect(association.name).to eq(:author)
      expect(association.source).to eq(:author)
    end

    it "recursively converts the nested descriptor" do
      expect(association.descriptor.name).to eq("DescriptorBuilderInnerSerializer")
      expect(association.descriptor.attributes).to eq([cg_attr(:id)])
    end
  end

  describe "has_one with a name: override" do
    subject(:association) { build(DescriptorBuilderRenamedHasOneSerializer).associations.first }

    # The footgun: name: overrides the OUTPUT key; the positional is the READER.
    it "takes the output key from name: and the reader from the positional" do
      expect(association.name).to eq(:user)
      expect(association.source).to eq(:owner)
    end
  end

  describe "has_many association" do
    subject(:association) { build(DescriptorBuilderHasManySerializer).associations.first }

    it "maps to a has_many association" do
      expect(association.kind).to eq(:has_many)
      expect(association.name).to eq(:comments)
      expect(association.source).to eq(:comments)
    end
  end

  describe "self-recursive serializer" do
    it "mirrors Panko's finite one-level recursion" do
      replies = build(DescriptorBuilderRecursiveSerializer).associations.first

      expect(replies.kind).to eq(:has_many)
      expect(replies.descriptor.attributes).to eq([cg_attr(:id)])
      expect(replies.descriptor.associations).to be_empty
    end
  end

  describe "the converted descriptor compiles" do
    it "compiles a method-field serializer in both modes (Symbol body needs parent_class)" do
      descriptor = build(DescriptorBuilderMethodSerializer)

      expect { Panko::CodeGen.compile(descriptor, output: :json) }.not_to raise_error
      expect { Panko::CodeGen.compile(descriptor, output: :hash) }.not_to raise_error
    end

    it "compiles a nested-association serializer" do
      expect {
        Panko::CodeGen.compile(build(DescriptorBuilderHasOneSerializer), output: :json)
      }.not_to raise_error
    end
  end
end
