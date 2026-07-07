# frozen_string_literal: true

require "bigdecimal"
require "panko/code_gen"

# Pins the Hash-mode datetime contract Panko's C extension established:
# datetime types render as their #as_json ISO-8601 String; everything else
# passes through untouched. Emitted into every Hash-mode field write via the
# +Panko::CodeGen.cast_datetime(...)+ wrapper (see FieldEmitters::Attribute /
# MethodAttribute). JSON mode never calls it — Oj (mode: :rails) formats these
# types identically on write.
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

    # Load-bearing: Symbol#as_json / BigDecimal#as_json return Strings, so a
    # blanket #as_json would silently change Hash mode's raw pass-through for
    # these. Only the four datetime classes may convert.
    context "when a Symbol" do
      let(:value) { :status }

      it "does not stringify the Symbol" do
        expect(cast).to eq(:status)
      end
    end

    context "when a BigDecimal" do
      let(:value) { BigDecimal("1.5") }

      it "does not stringify the BigDecimal" do
        expect(cast).to eq(BigDecimal("1.5"))
      end
    end
  end
end
