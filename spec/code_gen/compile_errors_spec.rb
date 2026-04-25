# frozen_string_literal: true

require "serializers_code_gen"

RSpec.describe "Compile-time errors" do
  describe "Error hierarchy" do
    it "Error subclasses StandardError" do
      expect(SerializersCodeGen::Error.superclass).to eq(StandardError)
    end

    it "DescriptorError and CompileError are direct children of Error" do
      expect(SerializersCodeGen::DescriptorError.superclass).to eq(SerializersCodeGen::Error)
      expect(SerializersCodeGen::CompileError.superclass).to eq(SerializersCodeGen::Error)
    end

    it "NameCollisionError, UnknownSourceError, ArityError subclass CompileError" do
      expect(SerializersCodeGen::NameCollisionError.superclass).to eq(SerializersCodeGen::CompileError)
      expect(SerializersCodeGen::UnknownSourceError.superclass).to eq(SerializersCodeGen::CompileError)
      expect(SerializersCodeGen::ArityError.superclass).to eq(SerializersCodeGen::CompileError)
    end
  end

  describe "DescriptorError — structural, at Data.new" do
    describe "Descriptor (S1.4)" do
      pending "raises when name is nil"
      pending "raises when name is an empty String"
      pending "raises when models contains a non-Class element"
      pending "raises when attributes contains a non-Attribute element"
      pending "raises when method_attributes contains a non-MethodAttribute element"
      pending "raises when associations contains a non-Association element"
    end

    describe "Attribute (S1.3)" do
      it "constructs a frozen instance with both fields populated" do
        attr = SerializersCodeGen::Attribute.new(name: :title, source: :raw_title)
        expect(attr).to be_frozen
        expect(attr.name).to eq(:title)
        expect(attr.source).to eq(:raw_title)
      end

      it "defaults source to name when omitted" do
        attr = SerializersCodeGen::Attribute.new(name: :title)
        expect(attr).to be_frozen
        expect(attr.source).to eq(:title)
      end

      it "raises when name is not a Symbol" do
        expect {
          SerializersCodeGen::Attribute.new(name: "title")
        }.to raise_error(SerializersCodeGen::DescriptorError)
      end

      it "raises when source is not a Symbol" do
        expect {
          SerializersCodeGen::Attribute.new(name: :title, source: "raw")
        }.to raise_error(SerializersCodeGen::DescriptorError)
      end
    end

    describe "MethodAttribute (S1.3)" do
      it "constructs a frozen instance with a Callable body" do
        ma = SerializersCodeGen::MethodAttribute.new(name: :likes_count, body: ->(r) { r.likes.count })
        expect(ma).to be_frozen
        expect(ma.name).to eq(:likes_count)
        expect(ma.body).to respond_to(:call)
      end

      it "raises when name is not a Symbol" do
        expect {
          SerializersCodeGen::MethodAttribute.new(name: "x", body: -> {})
        }.to raise_error(SerializersCodeGen::DescriptorError)
      end

      it "raises when body does not respond to #call" do
        expect {
          SerializersCodeGen::MethodAttribute.new(name: :x, body: 42)
        }.to raise_error(SerializersCodeGen::DescriptorError)
      end

      it "raises when body is an UnboundMethod (must be bound before inclusion)" do
        unbound = String.instance_method(:length)
        expect {
          SerializersCodeGen::MethodAttribute.new(name: :x, body: unbound)
        }.to raise_error(SerializersCodeGen::DescriptorError)
      end
    end

    describe "Association (S1.4)" do
      pending "raises when kind is not :has_one or :has_many"
      pending "raises when descriptor is not a Descriptor"
      pending "raises when if: is present but not a Callable"
    end
  end

  describe "CompileError subclasses" do
    describe "NameCollisionError (S9)" do
      pending "raises when two Attributes share a name"
      pending "raises when an Attribute and a MethodAttribute share a name"
      pending "raises when an Attribute and an Association share a name"
      pending "raises when a MethodAttribute and an Association share a name"
      pending "names the nested Descriptor when collision is inside a nested Descriptor"
      pending "does not raise when the same name appears at different levels"
    end

    describe "UnknownSourceError (S6)" do
      pending "raises when source is neither a column nor an instance method on the single Model"
      pending "raises when source has non-uniform backing across Models: [Class1, Class2]"
      pending "does not raise at Compile when Models is nil (defers to runtime NoMethodError)"
    end

    describe "ArityError (S4)" do
      pending "raises when MethodAttribute body has arity 3"
      pending "raises when MethodAttribute body has arity -1"
      pending "raises when MethodAttribute body has arity -2"
      pending "raises when Association if: has arity outside {0, 1, 2}"
      pending "compiles when MethodAttribute body has arity 0"
      pending "compiles when MethodAttribute body has arity 1"
      pending "compiles when MethodAttribute body has arity 2"
    end
  end

  describe "Message convention" do
    it "DescriptorError names the Field, kind, rule, and observed value (S1.3 / S1.4)" do
      expect {
        SerializersCodeGen::Attribute.new(name: "title")
      }.to raise_error(SerializersCodeGen::DescriptorError) { |err|
        expect(err.message).to include("Attribute#name")
        expect(err.message).to include("Symbol")
        expect(err.message).to include('"title"')
      }
    end

    pending "NameCollisionError names the Descriptor, Field name, and rule (S9)"
    pending "UnknownSourceError names the Descriptor, Field name, rule, and observed Source (S6)"
    pending "ArityError matches the docs/errors.md § Message convention example (S4)"
  end

  describe "SKIP singleton (S1.3)" do
    it "is identity-stable via #equal?" do
      expect(SerializersCodeGen::SKIP.equal?(SerializersCodeGen::SKIP)).to be(true)
    end

    it "is frozen" do
      expect(SerializersCodeGen::SKIP).to be_frozen
    end
  end

  describe "Mode independence — semantic validation runs pre-Generator" do
    %i[json hash].each do |mode|
      context "in #{mode} Output Mode" do
        pending "NameCollisionError raises before Generator emit (S9)"
        pending "UnknownSourceError raises before Generator emit (S6)"
        pending "ArityError raises before Generator emit (S4)"
      end
    end
  end
end
