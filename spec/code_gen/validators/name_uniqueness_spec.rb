# frozen_string_literal: true

require "panko/code_gen"

RSpec.describe Panko::CodeGen::Validators::NameUniqueness do
  let(:config) { Panko::CodeGen::Config.new }
  let(:inner) {
    Panko::CodeGen::Descriptor.new(
      name: "InnerDescriptor", model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [], method_attributes: [], associations: []
    )
  }

  def descriptor_with(name: "PostDescriptor", attributes: [], method_attributes: [], associations: [])
    Panko::CodeGen::Descriptor.new(
      name: name,
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: attributes,
      method_attributes: method_attributes,
      associations: associations
    )
  end

  def attribute(name)
    Panko::CodeGen::Attribute.new(name: name)
  end

  def method_attribute(name, body = ->(_r) { :ok })
    Panko::CodeGen::MethodAttribute.new(name: name, body: body)
  end

  def association(name, descriptor)
    Panko::CodeGen::Association.new(name: name, kind: :has_one, descriptor: descriptor)
  end

  describe ".validate — within-kind collisions" do
    it "raises when two Attributes share a name" do
      descriptor = descriptor_with(attributes: [attribute(:id), attribute(:id)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        Panko::CodeGen::NameCollisionError,
        "PostDescriptor#id: Attribute and Attribute share name; every Field at the same level must have a unique name."
      )
    end

    it "raises when two MethodAttributes share a name" do
      descriptor = descriptor_with(
        method_attributes: [method_attribute(:computed), method_attribute(:computed)]
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        Panko::CodeGen::NameCollisionError,
        "PostDescriptor#computed: MethodAttribute and MethodAttribute share name; every Field at the same level must have a unique name."
      )
    end

    it "raises when two Associations share a name" do
      descriptor = descriptor_with(associations: [association(:author, inner), association(:author, inner)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        Panko::CodeGen::NameCollisionError,
        "PostDescriptor#author: Association and Association share name; every Field at the same level must have a unique name."
      )
    end
  end

  describe ".validate — cross-kind collisions" do
    it "raises when an Attribute and a MethodAttribute share a name" do
      descriptor = descriptor_with(
        attributes: [attribute(:id)],
        method_attributes: [method_attribute(:id)]
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        Panko::CodeGen::NameCollisionError,
        "PostDescriptor#id: Attribute and MethodAttribute share name; every Field at the same level must have a unique name."
      )
    end

    it "raises when an Attribute and an Association share a name" do
      descriptor = descriptor_with(
        attributes: [attribute(:author)],
        associations: [association(:author, inner)]
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        Panko::CodeGen::NameCollisionError,
        "PostDescriptor#author: Attribute and Association share name; every Field at the same level must have a unique name."
      )
    end

    it "raises when a MethodAttribute and an Association share a name" do
      descriptor = descriptor_with(
        method_attributes: [method_attribute(:author)],
        associations: [association(:author, inner)]
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        Panko::CodeGen::NameCollisionError,
        "PostDescriptor#author: MethodAttribute and Association share name; every Field at the same level must have a unique name."
      )
    end
  end

  describe ".validate — clean Descriptors" do
    it "does not raise when all Field names are unique within a level" do
      descriptor = descriptor_with(
        attributes: [attribute(:id), attribute(:title)],
        method_attributes: [method_attribute(:computed)],
        associations: [association(:author, inner)]
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end

    it "does not raise on a Descriptor with no Fields" do
      descriptor = descriptor_with
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end
  end

  describe ".validate — cross-level isolation" do
    it "does not raise when the same name appears at parent and nested levels" do
      nested = Panko::CodeGen::Descriptor.new(
        name: "AuthorDescriptor", model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [attribute(:id)],
        method_attributes: [], associations: []
      )
      outer = descriptor_with(
        attributes: [attribute(:id)],
        associations: [association(:author, nested)]
      )
      expect {
        described_class.validate(outer, output: :json, config: config)
      }.not_to raise_error
    end
  end

  describe ".validate — nested Descriptor walk" do
    it "raises when the collision is inside a nested Descriptor and names the nested Descriptor" do
      nested = Panko::CodeGen::Descriptor.new(
        name: "AuthorDescriptor", model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [attribute(:name)],
        method_attributes: [],
        associations: [association(:name, inner)]
      )
      outer = descriptor_with(associations: [association(:author, nested)])
      expect {
        described_class.validate(outer, output: :json, config: config)
      }.to raise_error(
        Panko::CodeGen::NameCollisionError,
        "AuthorDescriptor#name: Attribute and Association share name; every Field at the same level must have a unique name."
      )
    end
  end

  describe ".validate — cycle / shared-subtree handling" do
    it "validates a shared inner Descriptor referenced from two Associations without re-walking" do
      shared = Panko::CodeGen::Descriptor.new(
        name: "SharedDescriptor", model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [attribute(:id)],
        method_attributes: [], associations: []
      )
      assoc1 = Panko::CodeGen::Association.new(name: :a, kind: :has_one, descriptor: shared)
      assoc2 = Panko::CodeGen::Association.new(name: :b, kind: :has_one, descriptor: shared)
      outer = descriptor_with(associations: [assoc1, assoc2])
      expect {
        described_class.validate(outer, output: :json, config: config)
      }.not_to raise_error
    end

    it "does not infinite-loop on a self-referencing Descriptor" do
      parent = Panko::CodeGen::Descriptor.new(
        name: "CommentDescriptor", model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [attribute(:body)],
        method_attributes: [], associations: []
      )
      parent.associations << Panko::CodeGen::Association.new(
        name: :replies, kind: :has_many, descriptor: parent
      )
      expect {
        described_class.validate(parent, output: :json, config: config)
      }.not_to raise_error
    end
  end

  describe ".validate — no Generated Class produced on raise" do
    it "raises before Panko::CodeGen.compile emits any source" do
      bad = descriptor_with(attributes: [attribute(:id)], method_attributes: [method_attribute(:id)])
      generated_class = nil
      expect {
        generated_class = Panko::CodeGen.compile(bad, output: :json, config: config)
      }.to raise_error(Panko::CodeGen::NameCollisionError)
      expect(generated_class).to be_nil
    end
  end

  describe "registration in the Validator orchestrator" do
    it "is included in Validator::DEFAULT_RULES" do
      expect(Panko::CodeGen::Validators::Validator::DEFAULT_RULES)
        .to include(described_class)
    end

    it "is registered immediately after SourceResolution" do
      rules = Panko::CodeGen::Validators::Validator::DEFAULT_RULES
      source_index = rules.index(Panko::CodeGen::Validators::SourceResolution)
      uniqueness_index = rules.index(described_class)
      expect(uniqueness_index).to eq(source_index + 1)
    end

    it "is invoked by the orchestrator on Compile" do
      bad = descriptor_with(attributes: [attribute(:id), attribute(:id)])
      expect {
        Panko::CodeGen::Validators::Validator.new.validate(bad, output: :json, config: config)
      }.to raise_error(Panko::CodeGen::NameCollisionError, /Attribute and Attribute share name/)
    end
  end
end
