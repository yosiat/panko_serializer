# frozen_string_literal: true

require "serializers_code_gen"

RSpec.describe SerializersCodeGen::Validators::SymbolBodyDispatch do
  let(:config) { SerializersCodeGen::Config.new }

  def descriptor_with(
    name: "PostDescriptor",
    method_attributes: [],
    associations: [],
    parent_class: nil
  )
    SerializersCodeGen::Descriptor.new(
      name: name,
      models: nil,
      attributes: [],
      method_attributes: method_attributes,
      associations: associations,
      parent_class: parent_class
    )
  end

  def method_attribute(name, body)
    SerializersCodeGen::MethodAttribute.new(name: name, body: body)
  end

  describe ".validate — Symbol-body legitimacy" do
    it "raises SymbolBodyError when a Symbol-body MethodAttribute sits in a Descriptor with parent_class: nil" do
      descriptor = descriptor_with(
        method_attributes: [method_attribute(:greeting, :greeting)],
        parent_class: nil
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::SymbolBodyError,
        "PostDescriptor#greeting: MethodAttribute#body is a Symbol but Descriptor#parent_class is nil; " \
        "Symbol-body requires a parent class to dispatch against."
      )
    end

    it "accepts a Symbol-body MethodAttribute when parent_class is a Class" do
      descriptor = descriptor_with(
        method_attributes: [method_attribute(:greeting, :greeting)],
        parent_class: Object
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end

    it "accepts a Callable-body MethodAttribute regardless of parent_class state (nil)" do
      descriptor = descriptor_with(
        method_attributes: [method_attribute(:computed, ->(_r) { :ok })],
        parent_class: nil
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end

    it "accepts a Callable-body MethodAttribute regardless of parent_class state (Class)" do
      descriptor = descriptor_with(
        method_attributes: [method_attribute(:computed, ->(_r) { :ok })],
        parent_class: Object
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end
  end

  describe ".validate — nested Descriptor walk" do
    it "raises when the Symbol-body sits one level deep under a parent_class: nil Descriptor" do
      inner = SerializersCodeGen::Descriptor.new(
        name: "AuthorDescriptor", models: nil,
        attributes: [],
        method_attributes: [method_attribute(:full_name, :full_name)],
        associations: [],
        parent_class: nil
      )
      assoc = SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: inner)
      outer = descriptor_with(associations: [assoc], parent_class: Object)
      expect {
        described_class.validate(outer, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::SymbolBodyError,
        "AuthorDescriptor#full_name: MethodAttribute#body is a Symbol but Descriptor#parent_class is nil; " \
        "Symbol-body requires a parent class to dispatch against."
      )
    end

    it "does not raise when each level of nested Descriptors with Symbol-body sets parent_class" do
      inner = SerializersCodeGen::Descriptor.new(
        name: "AuthorDescriptor", models: nil,
        attributes: [],
        method_attributes: [method_attribute(:full_name, :full_name)],
        associations: [],
        parent_class: Object
      )
      assoc = SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: inner)
      outer = descriptor_with(
        method_attributes: [method_attribute(:greeting, :greeting)],
        associations: [assoc],
        parent_class: Object
      )
      expect {
        described_class.validate(outer, output: :json, config: config)
      }.not_to raise_error
    end
  end

  describe ".validate — cycle / shared-subtree handling" do
    it "validates a shared inner Descriptor referenced from two Associations without re-walking" do
      shared = SerializersCodeGen::Descriptor.new(
        name: "SharedDescriptor", models: nil,
        attributes: [],
        method_attributes: [method_attribute(:fld, ->(_r) { :ok })],
        associations: [],
        parent_class: nil
      )
      assoc1 = SerializersCodeGen::Association.new(name: :a, kind: :has_one, descriptor: shared)
      assoc2 = SerializersCodeGen::Association.new(name: :b, kind: :has_one, descriptor: shared)
      outer = descriptor_with(associations: [assoc1, assoc2], parent_class: nil)
      expect {
        described_class.validate(outer, output: :json, config: config)
      }.not_to raise_error
    end

    it "does not infinite-loop on a self-referencing Descriptor" do
      parent = SerializersCodeGen::Descriptor.new(
        name: "CommentDescriptor", models: nil,
        attributes: [],
        method_attributes: [method_attribute(:body, ->(_r) { :ok })],
        associations: [],
        parent_class: nil
      )
      parent.associations << SerializersCodeGen::Association.new(
        name: :replies, kind: :has_many, descriptor: parent
      )
      expect {
        described_class.validate(parent, output: :json, config: config)
      }.not_to raise_error
    end
  end

  describe ".validate — no Generated Class produced on raise" do
    it "raises before SerializersCodeGen.compile emits any source" do
      bad = descriptor_with(
        method_attributes: [method_attribute(:greeting, :greeting)],
        parent_class: nil
      )
      generated_class = nil
      expect {
        generated_class = SerializersCodeGen.compile(bad, output: :json, config: config)
      }.to raise_error(SerializersCodeGen::SymbolBodyError)
      expect(generated_class).to be_nil
    end
  end

  describe "registration in the Validator orchestrator" do
    it "is included in Validator::DEFAULT_RULES" do
      expect(SerializersCodeGen::Validators::Validator::DEFAULT_RULES)
        .to include(described_class)
    end

    it "is registered as the 4th rule (after CallableArity, SourceResolution, NameUniqueness)" do
      rules = SerializersCodeGen::Validators::Validator::DEFAULT_RULES
      expect(rules).to eq([
        SerializersCodeGen::Validators::CallableArity,
        SerializersCodeGen::Validators::SourceResolution,
        SerializersCodeGen::Validators::NameUniqueness,
        described_class
      ])
    end

    it "is invoked by the orchestrator on Compile" do
      bad = descriptor_with(
        method_attributes: [method_attribute(:greeting, :greeting)],
        parent_class: nil
      )
      expect {
        SerializersCodeGen::Validators::Validator.new.validate(bad, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::SymbolBodyError,
        /MethodAttribute#body is a Symbol but Descriptor#parent_class is nil/
      )
    end
  end
end
