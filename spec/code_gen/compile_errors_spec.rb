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
      pending "raises when name is not a Symbol"
      pending "raises when source is not a Symbol"
    end

    describe "MethodAttribute (S1.3)" do
      pending "raises when body does not respond to #call"
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
    pending "DescriptorError names the Descriptor, Field, kind, rule, and observed value (S1.3 / S1.4)"
    pending "NameCollisionError names the Descriptor, Field name, and rule (S9)"
    pending "UnknownSourceError names the Descriptor, Field name, rule, and observed Source (S6)"
    pending "ArityError matches the docs/errors.md § Message convention example (S4)"
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
