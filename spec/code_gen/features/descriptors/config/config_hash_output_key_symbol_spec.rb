# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "config/config_hash_output_key_symbol"

# Hash mode only: JSON object keys are always Strings, so the knob has no effect there.
RSpec.describe "Generated Class for Fixtures::ConfigHashOutputKeySymbol" do
  let(:descriptor) { Fixtures::ConfigHashOutputKeySymbol::DESCRIPTOR }
  let(:config) { Fixtures::ConfigHashOutputKeySymbol::CONFIG }
  let(:generated_class) { Panko::CodeGen.compile(descriptor, output: :hash, config: config) }
  let(:generated) { generated_class.new(descriptor: descriptor) }

  describe "#serialize_one with hash_output_key_type: :symbol" do
    it "emits Symbol-keyed output from a String-keyed Hash record" do
      record = {"id" => 1, "name" => "Alice"}
      expect(generated.serialize_one(record)).to eq({id: 1, name: "Alice"})
    end

    it "emits Symbol-keyed output from a PORO Record (Struct)" do
      record = Struct.new(:id, :name).new(2, "Bob")
      expect(generated.serialize_one(record)).to eq({id: 2, name: "Bob"})
    end

    it "produces no String keys in the output (no mixed-key shape)" do
      record = {"id" => 1, "name" => "Alice"}
      output = generated.serialize_one(record)
      expect(output.keys).to all(be_a(Symbol))
    end
  end

  describe "#serialize_many with hash_output_key_type: :symbol" do
    it "emits an Array of Symbol-keyed Hashes" do
      records = [{"id" => 1, "name" => "Alice"}, {"id" => 2, "name" => "Bob"}]
      expect(generated.serialize_many(records)).to eq([
        {id: 1, name: "Alice"},
        {id: 2, name: "Bob"}
      ])
    end
  end

  describe "default String-key form is unaffected by this fixture" do
    let(:default_config) { Panko::CodeGen::Config.new }
    let(:generated_class) { Panko::CodeGen.compile(descriptor, output: :hash, config: default_config) }
    let(:generated) { generated_class.new(descriptor: descriptor) }

    it "emits String-keyed output when compiled with the default Config" do
      record = {"id" => 1, "name" => "Alice"}
      expect(generated.serialize_one(record)).to eq({"id" => 1, "name" => "Alice"})
    end
  end

  describe "uniform propagation through nested Descriptors" do
    # The fixture has no Associations, so the nested shape is built here.
    it "emits Symbol keys at every depth (has_one and has_many)" do
      inner = Panko::CodeGen::Descriptor.new(
        name: "ConfigHashOutputKeySymbolInnerSerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [
          Panko::CodeGen::Attribute.new(name: :id, source: :id),
          Panko::CodeGen::Attribute.new(name: :body, source: :body)
        ],
        method_attributes: [],
        associations: []
      )
      outer = Panko::CodeGen::Descriptor.new(
        name: "ConfigHashOutputKeySymbolOuterSerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [
          Panko::CodeGen::Attribute.new(name: :id, source: :id)
        ],
        method_attributes: [],
        associations: [
          Panko::CodeGen::Association.new(name: :inner, kind: :has_one, descriptor: inner),
          Panko::CodeGen::Association.new(name: :items, kind: :has_many, descriptor: inner)
        ]
      )
      generated = Panko::CodeGen.compile(outer, output: :hash, config: config).new(descriptor: outer)
      record = {
        "id" => 1,
        "inner" => {"id" => 7, "body" => "hi"},
        "items" => [
          {"id" => 11, "body" => "first"},
          {"id" => 12, "body" => "second"}
        ]
      }
      expect(generated.serialize_one(record)).to eq({
        id: 1,
        inner: {id: 7, body: "hi"},
        items: [
          {id: 11, body: "first"},
          {id: 12, body: "second"}
        ]
      })
    end
  end
end
