# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"

RSpec.describe SerializersCodeGen::Filter do
  describe ".wrap" do
    it "returns Filter::NONE for nil" do
      expect(described_class.wrap(nil)).to equal(SerializersCodeGen::Filter::NONE)
    end

    it "returns Filter::NONE for an empty Hash" do
      expect(described_class.wrap({})).to equal(SerializersCodeGen::Filter::NONE)
    end

    it "raises NotImplementedError referencing S14.2 for non-empty Hash" do
      expect { described_class.wrap({only: [:id]}) }
        .to raise_error(NotImplementedError, /S14\.2/)
    end
  end

  describe "::NONE" do
    let(:none) { SerializersCodeGen::Filter::NONE }

    it "is frozen" do
      expect(none).to be_frozen
    end

    it "is a stable singleton via #equal?" do
      expect(none).to equal(SerializersCodeGen::Filter::NONE)
    end

    it "drops? returns false for any integer index" do
      expect(none.drops?(0)).to be(false)
      expect(none.drops?(42)).to be(false)
    end

    it "child returns self for any source name" do
      expect(none.child(:author)).to equal(none)
      expect(none.child(:comments)).to equal(none)
    end

    it "none? returns true" do
      expect(none.none?).to be(true)
    end
  end
end
