# frozen_string_literal: true

require "panko/code_gen/code_builder"

RSpec.describe Panko::CodeGen::CodeBuilder do
  subject(:builder) { described_class.new }

  describe "#to_s" do
    it "is empty when no lines have been written" do
      expect(builder.to_s).to eq("")
    end

    it "joins sequential lines with a newline" do
      builder.line "foo"
      builder.line "bar"

      expect(builder.to_s).to eq("foo\nbar")
    end
  end

  describe "#indent" do
    it "indents lines inside the block by two spaces" do
      builder.line "outer"
      builder.indent do
        builder.line "inner"
      end
      builder.line "outer again"

      expect(builder.to_s).to eq("outer\n  inner\nouter again")
    end

    it "compounds nested indent blocks" do
      builder.indent do
        builder.line "one"
        builder.indent do
          builder.line "two"
          builder.indent do
            builder.line "three"
          end
        end
      end

      expect(builder.to_s).to eq("  one\n    two\n      three")
    end

    it "restores the indent level when the block raises" do
      expect {
        builder.indent do
          raise "boom"
        end
      }.to raise_error("boom")

      builder.line "after"
      expect(builder.to_s).to eq("after")
    end
  end

  describe "#line" do
    it "emits an empty line at the top level when called with no argument" do
      builder.line "before"
      builder.line
      builder.line "after"

      expect(builder.to_s).to eq("before\n\nafter")
    end

    it "emits an indented blank line when called inside an indent block" do
      builder.indent do
        builder.line
      end

      expect(builder.to_s).to eq("  ")
    end
  end

  describe "#blank" do
    it "emits a truly empty line at the top level" do
      builder.line "before"
      builder.blank
      builder.line "after"

      expect(builder.to_s).to eq("before\n\nafter")
    end

    it "emits a truly empty line inside an indent block, ignoring indent" do
      builder.indent do
        builder.line "inner"
        builder.blank
        builder.line "still inner"
      end

      expect(builder.to_s).to eq("  inner\n\n  still inner")
    end
  end
end
