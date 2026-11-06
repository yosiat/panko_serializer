# frozen_string_literal: true

require "panko/code_gen"

RSpec.describe Panko::CodeGen::ActiveRecord::DefineAttributeMethods do
  describe ".ensure!" do
    it "calls #define_attribute_methods when #attribute_methods_generated? is false" do
      define_calls = 0
      generated = false
      klass = Class.new do
        define_singleton_method(:attribute_methods_generated?) { generated }
        define_singleton_method(:define_attribute_methods) do
          define_calls += 1
          generated = true
        end
      end
      described_class.ensure!(klass)
      expect(define_calls).to eq(1)
    end

    it "short-circuits when #attribute_methods_generated? is true" do
      define_calls = 0
      klass = Class.new do
        define_singleton_method(:attribute_methods_generated?) { true }
        define_singleton_method(:define_attribute_methods) { define_calls += 1 }
      end
      described_class.ensure!(klass)
      expect(define_calls).to eq(0)
    end

    it "is idempotent across repeat invocations on the same class" do
      define_calls = 0
      generated = false
      klass = Class.new do
        define_singleton_method(:attribute_methods_generated?) { generated }
        define_singleton_method(:define_attribute_methods) do
          define_calls += 1
          generated = true
        end
      end
      3.times { described_class.ensure!(klass) }
      expect(define_calls).to eq(1)
    end

    it "exercises the AR machinery on a real ActiveRecord::Base subclass" do
      # Earlier specs may already have generated +Post+'s methods, so only the end state is checked.
      described_class.ensure!(Post)
      expect(Post.attribute_methods_generated?).to be(true)
    end
  end
end
