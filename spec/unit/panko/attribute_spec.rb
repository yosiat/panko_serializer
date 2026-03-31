# frozen_string_literal: true

require "spec_helper"

describe Panko::Attribute do
  describe "#invalidate!" do
    it "clears @type and @cached_writer" do
      attr = Panko::Attribute.create(:name)
      attr.type = :string
      attr.cached_writer = proc {}

      attr.invalidate!

      expect(attr.type).to be_nil
      expect(attr.cached_writer).to be_nil
    end
  end

  describe "#alias_name=" do
    it "can set the alias name" do
      attr = Panko::Attribute.create(:name)
      attr.alias_name = "full_name"
      expect(attr.alias_name).to eq("full_name")
    end

    it "can change an existing alias name" do
      attr = Panko::Attribute.create(:name, alias_name: "first_name")
      attr.alias_name = "full_name"
      expect(attr.alias_name).to eq("full_name")
    end
  end

  describe "#name=" do
    it "is publicly callable" do
      attr = Panko::Attribute.create(:name)
      expect { attr.name = "title" }.not_to raise_error
      expect(attr.name).to eq("title")
    end
  end
end
