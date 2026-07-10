# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

RSpec.describe Panko::CodeGen::DateTimeFormat do
  subject(:formatted) { described_class.format_raw(raw) }

  describe "recognized DB datetime strings" do
    context "without fractional seconds" do
      let(:raw) { "2026-07-10 12:34:56" }

      it "splices the ISO-8601 shape with .000 milliseconds and Z" do
        expect(formatted).to eq("2026-07-10T12:34:56.000Z")
      end

      it "matches the type-cast #as_json rendering" do
        expect(formatted).to eq(Time.utc(2026, 7, 10, 12, 34, 56).as_json)
      end
    end

    context "with millisecond precision" do
      let(:raw) { "2026-07-10 12:34:56.789" }

      it "keeps the three fraction digits" do
        expect(formatted).to eq("2026-07-10T12:34:56.789Z")
      end
    end

    context "with microsecond precision" do
      let(:raw) { "2026-07-10 12:34:56.789123" }

      it "truncates (never rounds) to milliseconds, matching #xmlschema(3)" do
        expect(formatted).to eq("2026-07-10T12:34:56.789Z")
        expect(formatted).to eq(Time.utc(2026, 7, 10, 12, 34, 56, 789_123).as_json)
      end
    end

    context "with a single fraction digit" do
      let(:raw) { "2026-07-10 12:34:56.5" }

      it "zero-pads to milliseconds" do
        expect(formatted).to eq("2026-07-10T12:34:56.500Z")
      end
    end

    context "when already ISO-8601 UTC" do
      let(:raw) { "2026-07-10T12:34:56.789Z" }

      it "passes the same String through" do
        expect(formatted).to equal(raw)
      end
    end
  end

  describe "unrecognized values fall back to nil" do
    context "when nil" do
      let(:raw) { nil }

      it { is_expected.to be_nil }
    end

    context "when a Time (dirty attribute holding the cast value)" do
      let(:raw) { Time.utc(2026, 7, 10, 12, 34, 56) }

      it { is_expected.to be_nil }
    end

    context "when a date-only string" do
      let(:raw) { "2026-07-10" }

      it { is_expected.to be_nil }
    end

    context "when a 19+ byte string without the datetime shape" do
      let(:raw) { "certainly not a datetime value" }

      it { is_expected.to be_nil }
    end
  end
end
