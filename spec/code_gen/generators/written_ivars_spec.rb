# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

RSpec.describe Panko::CodeGen::Generators::WrittenIvars do
  describe ".of" do
    it "returns nothing for methods that only read" do
      klass = Class.new do
        def label = "#{@prefix} #{object}"
      end

      expect(described_class.of(klass)).to eq([])
    end

    it "names the ivars set by def, define_method, blocks and private helpers" do
      klass = Class.new do
        def memo = (@memo ||= 1)

        define_method(:defined_memo) { @defined_memo = 2 }

        def in_block = [1].each { @in_block = 3 }

        private def helper = (@helper = 4)
      end

      expect(described_class.of(klass)).to contain_exactly(:@memo, :@defined_memo, :@in_block, :@helper)
    end

    it "names the ivars set by parent classes and included modules" do
      mixin = Module.new { def mixed = (@mixed = 1) }
      parent = Class.new { def inherited_memo = (@inherited_memo = 1) }
      klass = Class.new(parent) { include mixin }

      expect(described_class.of(klass)).to contain_exactly(:@mixed, :@inherited_memo)
    end

    it "names the ivar behind an attr_writer and ignores an attr_reader" do
      klass = Class.new do
        attr_reader :read_only
        attr_writer :cached
      end

      expect(described_class.of(klass)).to eq([:@cached])
    end

    it "reads locals and literal arrays named like instructions as data" do
      klass = Class.new do
        def notify(send, setinstancevariable) = [send, setinstancevariable]

        def literal = %i[send setinstancevariable instance_variable_set]

        def forwarded(...) = notify(...)
      end

      expect(described_class.of(klass)).to eq([])
    end

    it "returns nil when a block calls instance_variable_set" do
      klass = Class.new do
        def dynamic = [object].each { |name| instance_variable_set(:"@#{name}", 1) }
      end

      expect(described_class.of(klass)).to be_nil
    end

    it "skips initialize, which never runs on a Generated Class instance" do
      klass = Class.new do
        def initialize = (@options = {})
      end

      expect(described_class.of(klass)).to eq([])
    end

    it "returns nil when a method sets an ivar through instance_variable_set" do
      klass = Class.new do
        def dynamic = instance_variable_set(:"@#{object}", 1)
      end

      expect(described_class.of(klass)).to be_nil
    end

    it "returns nil for a method with neither bytecode nor a source location" do
      klass = Class.new
      klass.send(:define_method, :native, Kernel.instance_method(:hash))

      expect(described_class.of(klass)).to be_nil
    end
  end
end
