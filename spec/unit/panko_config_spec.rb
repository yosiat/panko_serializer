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
    example.run
  ensure
    described_class.auto_specialization.capacity = original_capacity
    described_class.auto_specialization.enabled = original_enabled
    described_class.writer_pool_max_bytes = original_writer_pool_max_bytes
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

  describe "Panko.configure" do
    it "yields the Config for block-style assignment" do
      Panko.configure do |config|
        config.auto_specialization.capacity = custom_capacity
      end
      expect(described_class.auto_specialization.capacity).to eq(custom_capacity)
    end
  end
end
