# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

# Cross-cutting +SKIP+ contract — the 7-item enumeration. JSON/Hash
# parity is iterated at the describe block. Fixtures are
# inline minimal Descriptors (1–3 Method Attributes each); the
# +shallow_specialized+ snapshot in S6 pins the emit bytes — this file
# pins the runtime semantics.
RSpec.describe "SKIP — Method Attribute identity-compare elision" do
  def descriptor_with(name: "SkipDescriptor", attributes: [], method_attributes: [])
    Panko::CodeGen::Descriptor.new(
      name: name,
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: attributes,
      method_attributes: method_attributes,
      associations: []
    )
  end

  def attribute(name)
    Panko::CodeGen::Attribute.new(name: name)
  end

  def method_attribute(name, body)
    Panko::CodeGen::MethodAttribute.new(name: name, body: body)
  end

  def compile(descriptor, mode)
    Panko::CodeGen.compile(descriptor, output: mode).new(descriptor: descriptor)
  end

  describe "(1) returning SKIP omits the Field entirely" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "drops the key and the value" do
          descriptor = descriptor_with(
            method_attributes: [
              method_attribute(:hidden, ->(_record, _context) { Panko::CodeGen::SKIP })
            ]
          )
          generated = compile(descriptor, mode)
          expected = (mode == :json) ? "{}" : {}
          expect(generated.serialize_one({})).to eq(expected)
        end
      end
    end
  end

  describe "(2) identity, not equality — a non-SKIP frozen Object.new emits" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "does not omit the Field" do
          descriptor = descriptor_with(
            method_attributes: [
              method_attribute(:fld, ->(_record, _context) { "present" })
            ]
          )
          generated = compile(descriptor, mode)
          expected = (mode == :json) ? '{"fld":"present"}' : {"fld" => "present"}
          expect(generated.serialize_one({})).to eq(expected)
        end

        it "treats a different frozen Object.new as a non-SKIP value (identity check)" do
          # Same shape as +SKIP+ (frozen +Object.new+), different identity —
          # under +equal?+ the field must emit; under +==+ it would also
          # not match SKIP, but the contract is identity, pinned here.
          descriptor = descriptor_with(
            method_attributes: [
              method_attribute(:fld, ->(_record, _context) { Object.new.freeze })
            ]
          )
          generated = compile(descriptor, mode)
          if mode == :json
            # Oj's :rails mode renders a generic Object's payload; the
            # exact byte shape is Oj-version-specific, so assert only
            # that the key is present (the load-bearing claim is
            # "field emits", not "renders to X").
            expect(generated.serialize_one({})).to include('"fld"')
          else
            output = generated.serialize_one({})
            expect(output).to have_key("fld")
            expect(output["fld"]).to be_an(Object)
          end
        end
      end
    end
  end

  describe "(3) works across Method Attribute arities 0, 1, 2" do
    bodies = {
      0 => -> { Panko::CodeGen::SKIP },
      1 => ->(_record) { Panko::CodeGen::SKIP },
      2 => ->(_record, _context) { Panko::CodeGen::SKIP }
    }

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        bodies.each do |arity, body|
          it "elides the Field for a SKIPping arity-#{arity} body" do
            descriptor = descriptor_with(
              method_attributes: [method_attribute(:hidden, body)]
            )
            generated = compile(descriptor, mode)
            expected = (mode == :json) ? "{}" : {}
            expect(generated.serialize_one({})).to eq(expected)
          end
        end
      end
    end
  end

  describe "(4) adjacent Fields emit correctly when neighbouring a SKIPped Method Attribute" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "emits the Attribute before and the Method Attribute after the SKIPping Method Attribute" do
          descriptor = descriptor_with(
            attributes: [attribute(:before)],
            method_attributes: [
              method_attribute(:hidden, ->(_record, _context) { Panko::CodeGen::SKIP }),
              method_attribute(:after, ->(_record, _context) { "present" })
            ]
          )
          generated = compile(descriptor, mode)
          record = {"before" => 1}
          expected = (mode == :json) ? '{"before":1,"after":"present"}' : {"before" => 1, "after" => "present"}
          expect(generated.serialize_one(record)).to eq(expected)
        end
      end
    end
  end

  describe "(5) multiple SKIPping Method Attributes — each elides independently" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "omits all SKIPping Fields and keeps the surviving ones" do
          descriptor = descriptor_with(
            method_attributes: [
              method_attribute(:s1, ->(_record, _context) { Panko::CodeGen::SKIP }),
              method_attribute(:keep, ->(_record, _context) { "yes" }),
              method_attribute(:s2, ->(_record, _context) { Panko::CodeGen::SKIP })
            ]
          )
          generated = compile(descriptor, mode)
          expected = (mode == :json) ? '{"keep":"yes"}' : {"keep" => "yes"}
          expect(generated.serialize_one({})).to eq(expected)
        end
      end
    end
  end

  describe "(6) singleton identity — Panko::CodeGen::SKIP is frozen and equal? to itself" do
    it "is frozen" do
      expect(Panko::CodeGen::SKIP).to be_frozen
    end

    it "is equal? to itself across module references (single object identity)" do
      expect(Panko::CodeGen::SKIP).to equal(Panko::CodeGen::SKIP)
    end

    it "is not equal? to a different frozen Object.new (separate identity)" do
      expect(Panko::CodeGen::SKIP).not_to equal(Object.new.freeze)
    end
  end
end
