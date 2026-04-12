# frozen_string_literal: true

require "spec_helper"

describe Panko::CodeGen do
  after do
    Panko::CodeGen.enable!
  end

  describe ".enabled?" do
    it "is enabled by default" do
      expect(Panko::CodeGen.enabled?).to be true
    end
  end

  describe ".disable!" do
    it "disables code generation" do
      Panko::CodeGen.disable!
      expect(Panko::CodeGen.enabled?).to be false
    end
  end

  describe ".enable!" do
    it "re-enables code generation after disable" do
      Panko::CodeGen.disable!
      Panko::CodeGen.enable!
      expect(Panko::CodeGen.enabled?).to be true
    end
  end
end
