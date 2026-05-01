# frozen_string_literal: true

require "serializers_code_gen"

RSpec.describe SerializersCodeGen::Config do
  describe ".new with no arguments" do
    subject(:config) { described_class.new }

    it "defaults null_for_missing_has_one to true" do
      expect(config.null_for_missing_has_one).to be(true)
    end

    it "defaults supports_root_key to false" do
      expect(config.supports_root_key).to be(false)
    end

    it "defaults hash_record_key_type to :string" do
      expect(config.hash_record_key_type).to eq(:string)
    end

    it "defaults hash_output_key_type to :string" do
      expect(config.hash_output_key_type).to eq(:string)
    end

    it "defaults json_column_emit to :wire_format" do
      expect(config.json_column_emit).to eq(:wire_format)
    end

    it "returns a frozen instance" do
      expect(config).to be_frozen
    end
  end

  describe ".new with a single override" do
    it "overrides only supports_root_key, leaving the rest at their defaults" do
      config = described_class.new(supports_root_key: true)

      expect(config.supports_root_key).to be(true)
      expect(config.null_for_missing_has_one).to be(true)
      expect(config.hash_record_key_type).to eq(:string)
      expect(config.hash_output_key_type).to eq(:string)
    end

    it "overrides only hash_record_key_type" do
      config = described_class.new(hash_record_key_type: :symbol)

      expect(config.hash_record_key_type).to eq(:symbol)
      expect(config.hash_output_key_type).to eq(:string)
    end

    it "overrides only hash_output_key_type" do
      config = described_class.new(hash_output_key_type: :symbol)

      expect(config.hash_output_key_type).to eq(:symbol)
      expect(config.hash_record_key_type).to eq(:string)
    end

    it "accepts both enum values for the hash key type fields" do
      expect {
        described_class.new(hash_record_key_type: :symbol, hash_output_key_type: :symbol)
      }.not_to raise_error
    end

    it "overrides only json_column_emit" do
      config = described_class.new(json_column_emit: :html_safe)

      expect(config.json_column_emit).to eq(:html_safe)
      expect(config.hash_output_key_type).to eq(:string)
    end

    it "accepts :html_safe for json_column_emit" do
      expect {
        described_class.new(json_column_emit: :html_safe)
      }.not_to raise_error
    end

    it "accepts :wire_format for json_column_emit" do
      expect {
        described_class.new(json_column_emit: :wire_format)
      }.not_to raise_error
    end
  end

  describe "structural validation at .new" do
    it "raises DescriptorError when hash_record_key_type is not in {:string, :symbol}" do
      expect {
        described_class.new(hash_record_key_type: :foo)
      }.to raise_error(SerializersCodeGen::DescriptorError)
    end

    it "raises DescriptorError when hash_output_key_type is not in {:string, :symbol}" do
      expect {
        described_class.new(hash_output_key_type: :foo)
      }.to raise_error(SerializersCodeGen::DescriptorError)
    end

    it "raises DescriptorError when hash_record_key_type is a String, not a Symbol" do
      expect {
        described_class.new(hash_record_key_type: "string")
      }.to raise_error(SerializersCodeGen::DescriptorError)
    end

    it "raises DescriptorError when hash_output_key_type is nil" do
      expect {
        described_class.new(hash_output_key_type: nil)
      }.to raise_error(SerializersCodeGen::DescriptorError)
    end

    it "raises ArgumentError when json_column_emit is not in {:wire_format, :html_safe}" do
      expect {
        described_class.new(json_column_emit: :foo)
      }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when json_column_emit is nil" do
      expect {
        described_class.new(json_column_emit: nil)
      }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when json_column_emit is a String, not a Symbol" do
      expect {
        described_class.new(json_column_emit: "wire_format")
      }.to raise_error(ArgumentError)
    end
  end

  describe "error message format" do
    it "names the offending field and the observed value for hash_record_key_type" do
      expect {
        described_class.new(hash_record_key_type: :foo)
      }.to raise_error(
        SerializersCodeGen::DescriptorError,
        "Config#hash_record_key_type: invalid value :foo; must be :string or :symbol."
      )
    end

    it "names the offending field and the observed value for hash_output_key_type" do
      expect {
        described_class.new(hash_output_key_type: "string")
      }.to raise_error(
        SerializersCodeGen::DescriptorError,
        'Config#hash_output_key_type: invalid value "string"; must be :string or :symbol.'
      )
    end

    it "names the offending field and the observed value for json_column_emit" do
      expect {
        described_class.new(json_column_emit: :foo)
      }.to raise_error(
        ArgumentError,
        "Config#json_column_emit: invalid value :foo; must be :wire_format or :html_safe."
      )
    end
  end
end
