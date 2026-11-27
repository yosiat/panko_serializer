# frozen_string_literal: true

require "spec_helper"

describe Panko::Config do
  let(:default_capacity) { 16 }
  let(:custom_capacity) { 32 }
  let(:default_writer_pool_max_bytes) { 1_048_576 }
  let(:custom_writer_pool_max_bytes) { 65_536 }

  # Settings are process-global; every example restores what it touched so
  # ordering can't leak configuration across the suite.
  around do |example|
    original_capacity = described_class.auto_specialization.capacity
    original_enabled = described_class.auto_specialization.enabled
    original_writer_pool_max_bytes = described_class.writer_pool_max_bytes
    original_key_transform = described_class.key_transform
    original_omit_nil_attributes = described_class.omit_nil_attributes
    example.run
  ensure
    described_class.auto_specialization.capacity = original_capacity
    described_class.auto_specialization.enabled = original_enabled
    described_class.writer_pool_max_bytes = original_writer_pool_max_bytes
    described_class.key_transform = original_key_transform
    described_class.omit_nil_attributes = original_omit_nil_attributes
  end

  describe ".auto_specialization" do
    it "defaults to enabled with the documented capacity" do
      expect(described_class.auto_specialization.enabled).to be(true)
      expect(described_class.auto_specialization.capacity).to eq(default_capacity)
    end

    describe "#capacity=" do
      it "accepts a positive Integer" do
        described_class.auto_specialization.capacity = custom_capacity
        expect(described_class.auto_specialization.capacity).to eq(custom_capacity)
      end

      it "rejects zero" do
        expect {
          described_class.auto_specialization.capacity = 0
        }.to raise_error(ArgumentError, /capacity: must be a positive Integer/)
      end

      it "rejects a negative Integer" do
        expect {
          described_class.auto_specialization.capacity = -1
        }.to raise_error(ArgumentError, /capacity: must be a positive Integer/)
      end

      it "rejects a non-Integer" do
        expect {
          described_class.auto_specialization.capacity = "many"
        }.to raise_error(ArgumentError, /capacity: must be a positive Integer/)
      end

      it "keeps the previous value after a rejected assignment" do
        begin
          described_class.auto_specialization.capacity = 0
        rescue ArgumentError
          nil
        end
        expect(described_class.auto_specialization.capacity).to eq(default_capacity)
      end
    end

    describe "#enabled=" do
      it "accepts false" do
        described_class.auto_specialization.enabled = false
        expect(described_class.auto_specialization.enabled).to be(false)
      end

      it "rejects a truthy non-Boolean" do
        expect {
          described_class.auto_specialization.enabled = :yes
        }.to raise_error(ArgumentError, /enabled: must be true or false/)
      end

      it "rejects nil" do
        expect {
          described_class.auto_specialization.enabled = nil
        }.to raise_error(ArgumentError, /enabled: must be true or false/)
      end
    end
  end

  describe ".writer_pool_max_bytes" do
    it "defaults to 1 MB" do
      expect(described_class.writer_pool_max_bytes).to eq(default_writer_pool_max_bytes)
    end

    it "accepts a positive Integer" do
      described_class.writer_pool_max_bytes = custom_writer_pool_max_bytes
      expect(described_class.writer_pool_max_bytes).to eq(custom_writer_pool_max_bytes)
    end

    it "rejects zero" do
      expect {
        described_class.writer_pool_max_bytes = 0
      }.to raise_error(ArgumentError, /writer_pool_max_bytes: must be a positive Integer/)
    end

    it "rejects a non-Integer" do
      expect {
        described_class.writer_pool_max_bytes = "1mb"
      }.to raise_error(ArgumentError, /writer_pool_max_bytes: must be a positive Integer/)
    end
  end

  describe ".key_transform" do
    it "defaults to nil" do
      expect(described_class.key_transform).to be_nil
    end

    it "accepts :camel_lower" do
      described_class.key_transform = :camel_lower
      expect(described_class.key_transform).to eq(:camel_lower)
    end

    it "accepts nil" do
      described_class.key_transform = :camel
      described_class.key_transform = nil
      expect(described_class.key_transform).to be_nil
    end

    it "rejects an unknown transform" do
      expect {
        described_class.key_transform = :kebab
      }.to raise_error(ArgumentError, /key_transform: must be :camel_lower, :camel, :dash, :underscore or nil/)
    end

    it "rejects the String spelling" do
      expect {
        described_class.key_transform = "camel_lower"
      }.to raise_error(ArgumentError, /key_transform: must be :camel_lower, :camel, :dash, :underscore or nil/)
    end
  end

  describe ".omit_nil_attributes" do
    it "defaults to false" do
      expect(described_class.omit_nil_attributes).to be(false)
    end

    it "accepts true" do
      described_class.omit_nil_attributes = true
      expect(described_class.omit_nil_attributes).to be(true)
    end

    it "rejects a truthy non-Boolean" do
      expect {
        described_class.omit_nil_attributes = 1
      }.to raise_error(ArgumentError, /omit_nil_attributes: must be true or false/)
    end

    it "rejects nil" do
      expect {
        described_class.omit_nil_attributes = nil
      }.to raise_error(ArgumentError, /omit_nil_attributes: must be true or false/)
    end
  end

  describe ".transform_key" do
    let(:key) { :home_address }

    it "keeps the key when no transform is set" do
      expect(described_class.transform_key(key)).to eq(key)
    end

    it "lower camelizes with :camel_lower" do
      described_class.key_transform = :camel_lower
      expect(described_class.transform_key(key)).to eq(:homeAddress)
    end

    it "camelizes with :camel" do
      described_class.key_transform = :camel
      expect(described_class.transform_key(key)).to eq(:HomeAddress)
    end

    it "dasherizes with :dash" do
      described_class.key_transform = :dash
      expect(described_class.transform_key(key)).to eq(:"home-address")
    end

    it "dasherizes a camelCase key with :dash" do
      described_class.key_transform = :dash
      expect(described_class.transform_key(:homeAddress)).to eq(:"home-address")
    end

    it "underscores a camelCase key with :underscore" do
      described_class.key_transform = :underscore
      expect(described_class.transform_key(:homeAddress)).to eq(key)
    end
  end

  describe "Panko.configure" do
    it "yields the Config for block-style assignment" do
      Panko.configure do |config|
        config.auto_specialization.capacity = custom_capacity
      end
      expect(described_class.auto_specialization.capacity).to eq(custom_capacity)
    end
  end
end
