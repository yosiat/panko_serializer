# frozen_string_literal: true

require "spec_helper"

RSpec.describe Panko::AttributesWriter::Plain do
  let(:plain_writer) { described_class.new }

  describe "#write_attributes" do
    let(:object) { double("test_object") }
    let(:attribute) { Panko::Attribute.create("name") }
    let(:writer) { double("writer") }

    it "reads attribute values using public_send" do
      # Set up the mock to return the expected value
      allow(object).to receive(:respond_to?).with(:name).and_return(true)
      allow(object).to receive(:public_send).with(:name).and_return("test_value")
      expect(writer).to receive(:push_value).with("test_value", "name")

      plain_writer.write_attributes(object, [attribute], writer)
    end

    it "handles SKIP constant" do
      skip_attribute = Panko::Attribute.create("SKIP")
      expect(writer).to receive(:push_value).with(Panko::Serializer::SKIP, "SKIP")

      plain_writer.write_attributes(object, [skip_attribute], writer)
    end

    it "falls back to instance variable access if method doesn't exist" do
      allow(object).to receive(:respond_to?).with(:name).and_return(false)
      allow(object).to receive(:instance_variable_get).with("@name").and_return("ivar_value")
      expect(writer).to receive(:push_value).with("ivar_value", "name")

      plain_writer.write_attributes(object, [attribute], writer)
    end

    it "handles multiple attributes" do
      attribute1 = Panko::Attribute.create("first_name")
      attribute2 = Panko::Attribute.create("last_name")

      allow(object).to receive(:respond_to?).with(:first_name).and_return(true)
      allow(object).to receive(:respond_to?).with(:last_name).and_return(true)
      allow(object).to receive(:public_send).with(:first_name).and_return("John")
      allow(object).to receive(:public_send).with(:last_name).and_return("Doe")

      expect(writer).to receive(:push_value).with("John", "first_name")
      expect(writer).to receive(:push_value).with("Doe", "last_name")

      plain_writer.write_attributes(object, [attribute1, attribute2], writer)
    end

    it "handles nil values gracefully" do
      allow(object).to receive(:respond_to?).with(:name).and_return(true)
      allow(object).to receive(:public_send).with(:name).and_return(nil)
      expect(writer).to receive(:push_value).with(nil, "name")

      plain_writer.write_attributes(object, [attribute], writer)
    end

    it "handles method errors gracefully" do
      allow(object).to receive(:respond_to?).with(:name).and_return(true)
      allow(object).to receive(:public_send).with(:name).and_raise(NoMethodError, "undefined method")
      expect(writer).to receive(:push_value).with(nil, "name")

      plain_writer.write_attributes(object, [attribute], writer)
    end
  end
end
