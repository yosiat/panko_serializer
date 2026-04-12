# frozen_string_literal: true

require "spec_helper"

describe Panko::CodeGen::FilterMask do
  describe "#initialize" do
    it "freezes attrs array" do
      mask = described_class.new(attrs: [true, false, true])
      expect(mask.attrs).to be_frozen
    end

    it "freezes optional arrays when provided" do
      mask = described_class.new(
        attrs: [true],
        method_fields: [false],
        has_one: [true],
        has_many: [false]
      )

      expect(mask.method_fields).to be_frozen
      expect(mask.has_one).to be_frozen
      expect(mask.has_many).to be_frozen
    end

    it "allows nil for optional arrays" do
      mask = described_class.new(attrs: [true])

      expect(mask.method_fields).to be_nil
      expect(mask.has_one).to be_nil
      expect(mask.has_many).to be_nil
      expect(mask.has_one_masks).to be_nil
      expect(mask.has_many_masks).to be_nil
    end

    it "freezes the mask itself" do
      mask = described_class.new(attrs: [true])
      expect(mask).to be_frozen
    end

    it "stores nested has_one_masks" do
      nested = described_class.new(attrs: [true, false])
      mask = described_class.new(
        attrs: [true],
        has_one: [true],
        has_one_masks: [nested]
      )

      expect(mask.has_one_masks).to eq([nested])
      expect(mask.has_one_masks).to be_frozen
    end

    it "stores nested has_many_masks" do
      nested = described_class.new(attrs: [false, true])
      mask = described_class.new(
        attrs: [true],
        has_many: [true],
        has_many_masks: [nested]
      )

      expect(mask.has_many_masks).to eq([nested])
      expect(mask.has_many_masks).to be_frozen
    end
  end

  describe "boolean array access" do
    it "provides positional inclusion checks" do
      mask = described_class.new(attrs: [true, false, true, false, true])

      expect(mask.attrs[0]).to be true
      expect(mask.attrs[1]).to be false
      expect(mask.attrs[2]).to be true
      expect(mask.attrs[3]).to be false
      expect(mask.attrs[4]).to be true
    end
  end
end
