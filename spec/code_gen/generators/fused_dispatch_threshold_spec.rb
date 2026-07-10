# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

RSpec.describe "Generic fused-dispatch threshold" do
  let(:generator) { Panko::CodeGen::Generator.new }
  let(:config) { Panko::CodeGen::Config.new }
  let(:threshold) { Panko::CodeGen::Generators::RecordAccess::Generic::FUSED_DISPATCH_MAX_FIELDS }

  def descriptor_with_fields(count, name)
    Panko::CodeGen::Descriptor.new(
      name: name,
      models: nil,
      attributes: (1..count).map { |i| Panko::CodeGen::Attribute.new(name: :"f_#{i}", source: :"f_#{i}") },
      method_attributes: [],
      associations: []
    )
  end

  let(:at_threshold) { descriptor_with_fields(threshold, "AtThresholdSerializer") }
  let(:over_threshold) { descriptor_with_fields(threshold + 1, "OverThresholdSerializer") }

  %i[json hash].each do |mode|
    context "with #{mode} Output Mode" do
      let(:helper_prefix) { (mode == :json) ? "_write_one" : "_to_hash" }

      it "emits the fused inline body at the threshold" do
        source = generator.emit(at_threshold, output: mode, config: config)

        expect(source).not_to include("def #{helper_prefix}_object")
        expect(source).not_to include("def #{helper_prefix}_hash")
      end

      it "emits the dispatcher + per-shape helpers over the threshold" do
        source = generator.emit(over_threshold, output: mode, config: config)

        expect(source).to include("def #{helper_prefix}_object(record,")
        expect(source).to include("def #{helper_prefix}_hash(record,")
        expect(source).to include("#{helper_prefix}_object(record,")
      end

      it "serializes every field through the split shape" do
        field_count = threshold + 1
        record_class = Struct.new(*(1..field_count).map { |i| :"f_#{i}" })
        record = record_class.new(*(1..field_count).to_a)

        split = Panko::CodeGen.compile(over_threshold, output: mode).new(descriptor: over_threshold)
        result = split.serialize_one(record)
        result = Oj.load(result) if mode == :json

        expect(result.size).to eq(field_count)
        expect(result["f_1"]).to eq(1)
        expect(result["f_#{field_count}"]).to eq(field_count)
      end
    end
  end
end
