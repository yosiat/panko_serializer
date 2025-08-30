# frozen_string_literal: true

require "spec_helper"

RSpec.describe Panko::AttributesWriter::HashWriter do
  let(:hash_writer) { described_class.new }

  describe "#write_attributes" do
    let(:object) { {"name" => "test_value", :symbol_key => "symbol_value"} }
    let(:attribute) { Panko::Attribute.create("name") }
    let(:symbol_attribute) { Panko::Attribute.create("symbol_key") }
    let(:writer) { double("writer") }

    it "reads attribute values using string keys" do
      expect(writer).to receive(:push_value).with("test_value", "name")

      hash_writer.write_attributes(object, [attribute], writer)
    end

    it "falls back to symbol keys if string key not found" do
      expect(writer).to receive(:push_value).with("symbol_value", "symbol_key")

      hash_writer.write_attributes(object, [symbol_attribute], writer)
    end

    it "handles multiple attributes" do
      attribute1 = Panko::Attribute.create("name")
      attribute2 = Panko::Attribute.create("symbol_key")

      expect(writer).to receive(:push_value).with("test_value", "name")
      expect(writer).to receive(:push_value).with("symbol_value", "symbol_key")

      hash_writer.write_attributes(object, [attribute1, attribute2], writer)
    end

    it "handles missing keys gracefully" do
      missing_attribute = Panko::Attribute.create("missing_key")
      expect(writer).to receive(:push_value).with(nil, "missing_key")

      hash_writer.write_attributes(object, [missing_attribute], writer)
    end

    it "handles nil values" do
      object_with_nil = {"name" => nil}
      expect(writer).to receive(:push_value).with(nil, "name")

      hash_writer.write_attributes(object_with_nil, [attribute], writer)
    end

    it "handles empty hash" do
      empty_hash = {}
      expect(writer).to receive(:push_value).with(nil, "name")

      hash_writer.write_attributes(empty_hash, [attribute], writer)
    end

    it "prioritizes string keys over symbol keys" do
      mixed_hash = {"name" => "string_value", :name => "symbol_value"}
      expect(writer).to receive(:push_value).with("string_value", "name")

      hash_writer.write_attributes(mixed_hash, [attribute], writer)
    end

    it "handles complex values" do
      complex_hash = {"name" => {"nested" => "value"}}
      expect(writer).to receive(:push_value).with({"nested" => "value"}, "name")

      hash_writer.write_attributes(complex_hash, [attribute], writer)
    end
  end
end
