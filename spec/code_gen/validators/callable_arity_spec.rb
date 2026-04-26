# frozen_string_literal: true

require "serializers_code_gen"

RSpec.describe SerializersCodeGen::Validators::CallableArity do
  let(:config) { SerializersCodeGen::Config.new }

  def descriptor_with(name: "PostDescriptor", method_attributes: [], associations: [])
    SerializersCodeGen::Descriptor.new(
      name: name,
      models: nil,
      attributes: [],
      method_attributes: method_attributes,
      associations: associations
    )
  end

  def method_attribute(name, body)
    SerializersCodeGen::MethodAttribute.new(name: name, body: body)
  end

  describe ".validate — MethodAttribute#body arity" do
    {
      0 => -> { :ok },
      1 => ->(_record) { :ok },
      2 => ->(_record, _context) { :ok }
    }.each do |arity, body|
      it "passes for arity #{arity}" do
        descriptor = descriptor_with(method_attributes: [method_attribute(:fld, body)])
        expect {
          described_class.validate(descriptor, output: :json, config: config)
        }.not_to raise_error
      end
    end

    {
      3 => ->(_a, _b, _c) { :ok },
      -1 => ->(*_args) { :ok },
      -2 => ->(_a, *_rest) { :ok }
    }.each do |arity, body|
      it "raises ArityError for arity #{arity}" do
        descriptor = descriptor_with(method_attributes: [method_attribute(:likes_count, body)])
        expect {
          described_class.validate(descriptor, output: :json, config: config)
        }.to raise_error(
          SerializersCodeGen::ArityError,
          "PostDescriptor#likes_count: MethodAttribute#body has arity #{arity}; must be 0, 1, or 2."
        )
      end
    end
  end

  describe ".validate — Association#if arity" do
    let(:inner) {
      SerializersCodeGen::Descriptor.new(
        name: "InnerDescriptor", models: nil,
        attributes: [], method_attributes: [], associations: []
      )
    }

    it "passes when if: is nil (no guard)" do
      assoc = SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: inner)
      descriptor = descriptor_with(associations: [assoc])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end

    it "passes for arity 2 if:" do
      assoc = SerializersCodeGen::Association.new(
        name: :author, kind: :has_one, descriptor: inner, if: ->(_r, _c) { true }
      )
      descriptor = descriptor_with(associations: [assoc])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end

    it "raises ArityError for arity 3 if:" do
      assoc = SerializersCodeGen::Association.new(
        name: :author, kind: :has_one, descriptor: inner, if: ->(_a, _b, _c) { true }
      )
      descriptor = descriptor_with(associations: [assoc])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::ArityError,
        "PostDescriptor#author: Association#if has arity 3; must be 0, 1, or 2."
      )
    end

    it "raises ArityError for variadic if: (arity -1)" do
      assoc = SerializersCodeGen::Association.new(
        name: :author, kind: :has_one, descriptor: inner, if: ->(*_args) { true }
      )
      descriptor = descriptor_with(associations: [assoc])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::ArityError,
        "PostDescriptor#author: Association#if has arity -1; must be 0, 1, or 2."
      )
    end
  end

  describe ".validate — nested Descriptor walk" do
    it "raises when a Method Attribute one level deep has bad arity" do
      inner = SerializersCodeGen::Descriptor.new(
        name: "AuthorDescriptor", models: nil,
        attributes: [],
        method_attributes: [method_attribute(:full_name, ->(_a, _b, _c) { :ok })],
        associations: []
      )
      assoc = SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: inner)
      outer = descriptor_with(associations: [assoc])
      expect {
        described_class.validate(outer, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::ArityError,
        "AuthorDescriptor#full_name: MethodAttribute#body has arity 3; must be 0, 1, or 2."
      )
    end
  end

  describe ".validate — cycle / shared-subtree handling" do
    it "validates a shared inner Descriptor referenced from two Associations without re-walking" do
      inner = SerializersCodeGen::Descriptor.new(
        name: "InnerDescriptor", models: nil, attributes: [],
        method_attributes: [method_attribute(:fld, ->(_r) { :ok })],
        associations: []
      )
      assoc1 = SerializersCodeGen::Association.new(name: :a, kind: :has_one, descriptor: inner)
      assoc2 = SerializersCodeGen::Association.new(name: :b, kind: :has_one, descriptor: inner)
      outer = descriptor_with(associations: [assoc1, assoc2])
      expect {
        described_class.validate(outer, output: :json, config: config)
      }.not_to raise_error
    end

    it "does not infinite-loop on a self-referencing Descriptor" do
      # Self-recursive shapes are constructed via the identity-keyed
      # cache scaffold in S5/S8; here we mutate a (non-frozen) Array
      # post-construction to install the back-reference, then prove the
      # validator's identity-cache short-circuits the cycle.
      parent = SerializersCodeGen::Descriptor.new(
        name: "CommentDescriptor", models: nil, attributes: [],
        method_attributes: [method_attribute(:body, ->(_r) { :ok })],
        associations: []
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
      bad = descriptor_with(method_attributes: [method_attribute(:bad, ->(_a, _b, _c) { :ok })])
      generated_class = nil
      expect {
        generated_class = SerializersCodeGen.compile(bad, output: :json, config: config)
      }.to raise_error(SerializersCodeGen::ArityError)
      expect(generated_class).to be_nil
    end
  end

  describe "registration in the Validator orchestrator" do
    it "is included in Validator::DEFAULT_RULES" do
      expect(SerializersCodeGen::Validators::Validator::DEFAULT_RULES)
        .to include(described_class)
    end

    it "is invoked by the orchestrator on Compile" do
      bad = descriptor_with(method_attributes: [method_attribute(:bad, ->(_a, _b, _c) { :ok })])
      expect {
        SerializersCodeGen::Validators::Validator.new.validate(bad, output: :json, config: config)
      }.to raise_error(SerializersCodeGen::ArityError, /MethodAttribute#body has arity 3/)
    end
  end
end
