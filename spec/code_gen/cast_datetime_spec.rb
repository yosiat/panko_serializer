# frozen_string_literal: true

require "bigdecimal"
require "panko/code_gen"

# Hash mode must produce the same values that Oj's +:rails+ mode writes in JSON mode.
RSpec.describe "Panko::CodeGen.cast_datetime" do
  subject(:cast) { Panko::CodeGen.cast_datetime(value) }

  describe "datetime types" do
    context "when a UTC Time" do
      let(:value) { Time.utc(2026, 7, 6, 19, 26, 36, 590_000) }

      it "renders the same ISO-8601 String that #as_json (and Oj :rails) produce" do
        expect(cast).to eq(value.as_json)
      end

      it "renders millisecond precision with a trailing Z" do
        expect(cast).to eq("2026-07-06T19:26:36.590Z")
      end
    end

    context "when a Date" do
      let(:value) { Date.new(2026, 7, 6) }

      it "renders the plain ISO date" do
        expect(cast).to eq(value.as_json)
      end
    end

    context "when a DateTime" do
      let(:value) { DateTime.new(2026, 7, 6, 19, 26, 36) }

      it "renders the DateTime #as_json String" do
        expect(cast).to eq(value.as_json)
      end
    end

    context "when an ActiveSupport::TimeWithZone" do
      let(:value) { Time.utc(2026, 7, 6, 19, 26, 36, 590_000).in_time_zone("UTC") }

      it "renders the zoned ISO-8601 String" do
        expect(cast).to eq(value.as_json)
      end
    end
  end

  describe "non-datetime values" do
    context "when nil" do
      let(:value) { nil }

      it "passes nil through" do
        expect(cast).to be_nil
      end
    end

    context "when an Integer" do
      let(:value) { 42 }

      it "passes the Integer through unchanged" do
        expect(cast).to eq(value)
      end
    end

    context "when a String" do
      let(:value) { "already a string" }

      it "passes the same String object through" do
        expect(cast).to equal(value)
      end
    end

    context "when a Symbol" do
      let(:value) { :status }

      it "stringifies the Symbol like #as_json" do
        expect(cast).to eq("status")
      end
    end

    context "when a BigDecimal" do
      let(:value) { BigDecimal("1.5") }

      it "stringifies the BigDecimal like #as_json" do
        expect(cast).to eq(BigDecimal("1.5").as_json)
      end
    end

    context "when a symbol-keyed Hash" do
      let(:value) { {api_key: "secret"} }

      it "stringifies the keys like #as_json" do
        expect(cast).to eq("api_key" => "secret")
      end
    end

    context "when an object with its own as_json" do
      let(:value) do
        Class.new {
          def as_json(*)
            {"id" => 7}
          end
        }.new
      end

      it "flattens it through its as_json" do
        expect(cast).to eq("id" => 7)
      end
    end
  end
end
