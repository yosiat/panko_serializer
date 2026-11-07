# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "shallow_generic"

RSpec.describe "JSON-mode WritersPool emit" do
  let(:descriptor) { Fixtures::ShallowGeneric::DESCRIPTOR }
  let(:generator) { Panko::CodeGen::Generator }

  describe "pooled writer" do
    let(:config) { Panko::CodeGen::Config.new }

    context "when ActiveSupport::IsolatedExecutionState is defined at Compile time" do
      before { stub_const("ActiveSupport::IsolatedExecutionState", Module.new) }

      let(:source) { generator.emit(descriptor, output: :json, config: config) }

      it "bakes the IsolatedExecutionState subclass name into the POOL constant" do
        expect(source).to include(
          "POOL = Panko::CodeGen::WritersPool::IsolatedExecutionState.new"
        )
      end

      it "does not emit a defined?(...) expression - the subclass is baked at Compile time" do
        expect(source).not_to include("defined?(ActiveSupport::IsolatedExecutionState)")
      end

      it "does not emit the ThreadLocal subclass" do
        expect(source).not_to include("WritersPool::ThreadLocal")
      end
    end

    context "when ActiveSupport::IsolatedExecutionState is undefined at Compile time" do
      before do
        if defined?(ActiveSupport::IsolatedExecutionState)
          hide_const("ActiveSupport::IsolatedExecutionState")
        end
      end

      let(:source) { generator.emit(descriptor, output: :json, config: config) }

      it "bakes the ThreadLocal subclass name into the POOL constant" do
        expect(source).to include(
          "POOL = Panko::CodeGen::WritersPool::ThreadLocal.new"
        )
      end

      it "does not emit a defined?(...) expression - the subclass is baked at Compile time" do
        expect(source).not_to include("defined?(ActiveSupport::IsolatedExecutionState)")
      end

      it "does not emit the IsolatedExecutionState subclass" do
        expect(source).not_to include("WritersPool::IsolatedExecutionState")
      end
    end

    it "wraps serialize_one in begin/ensure with POOL.checkout / POOL.checkin" do
      source = generator.emit(descriptor, output: :json, config: config)

      expect(source).to include("writer = POOL.checkout")
      expect(source).to include("POOL.checkin(writer, result)")
      expect(source).to match(/def serialize_one.*?writer = POOL\.checkout.*?result = nil.*?begin.*?ensure.*?POOL\.checkin\(writer, result\)/m)
    end

    it "wraps serialize_many in begin/ensure with POOL.checkout / POOL.checkin" do
      source = generator.emit(descriptor, output: :json, config: config)

      expect(source).to match(/def serialize_many.*?writer = POOL\.checkout.*?result = nil.*?begin.*?ensure.*?POOL\.checkin\(writer, result\)/m)
    end
  end
end
