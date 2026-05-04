# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"
require "shallow_generic"

# JSON-mode emit shape tests for the +Config#pool_writer+ knob (S16.2).
# These specs assert directly on the +Generator+'s source-string output —
# no +module_eval+, no snapshot files. The byte-identical rollback path
# (+pool_writer: false+) is pinned with a verbatim-string comparison
# against a small inline reference snippet so a regression in the
# unpooled emit tier surfaces here, before snapshots are regenerated.
RSpec.describe "JSON-mode WritersPool emit (S16.2)" do
  let(:descriptor) { Fixtures::ShallowGeneric::DESCRIPTOR }
  let(:generator) { SerializersCodeGen::Generator.new }

  describe "with Config#pool_writer: true" do
    let(:config) { SerializersCodeGen::Config.new(pool_writer: true) }

    context "when ActiveSupport::IsolatedExecutionState is defined at Compile time" do
      before { stub_const("ActiveSupport::IsolatedExecutionState", Module.new) }

      let(:source) { generator.emit(descriptor, output: :json, config: config) }

      it "bakes the IsolatedExecutionState subclass name into the POOL constant" do
        expect(source).to include(
          "POOL = SerializersCodeGen::WritersPool::IsolatedExecutionState.new(:_scg_writer__ShallowGenericSerializer_JSON)"
        )
      end

      it "does not emit a defined?(...) expression — the subclass is baked at Compile time" do
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
          "POOL = SerializersCodeGen::WritersPool::ThreadLocal.new(:_scg_writer__ShallowGenericSerializer_JSON)"
        )
      end

      it "does not emit a defined?(...) expression — the subclass is baked at Compile time" do
        expect(source).not_to include("defined?(ActiveSupport::IsolatedExecutionState)")
      end

      it "does not emit the IsolatedExecutionState subclass" do
        expect(source).not_to include("WritersPool::IsolatedExecutionState")
      end
    end

    it "wraps serialize_one in begin/ensure with POOL.checkout / POOL.checkin" do
      source = generator.emit(descriptor, output: :json, config: config)

      expect(source).to include("writer = POOL.checkout")
      expect(source).to include("POOL.checkin(writer)")
      expect(source).to match(/def serialize_one.*?writer = POOL\.checkout.*?begin.*?ensure.*?POOL\.checkin\(writer\)/m)
    end

    it "wraps serialize_many in begin/ensure with POOL.checkout / POOL.checkin" do
      source = generator.emit(descriptor, output: :json, config: config)

      expect(source).to match(/def serialize_many.*?writer = POOL\.checkout.*?begin.*?ensure.*?POOL\.checkin\(writer\)/m)
    end

    it "does not emit the inline Oj::StringWriter.new allocation in the pooled path" do
      source = generator.emit(descriptor, output: :json, config: config)

      expect(source).not_to include("Oj::StringWriter.new(mode: :rails)")
    end
  end

  describe "with Config#pool_writer: false" do
    let(:config) { SerializersCodeGen::Config.new(pool_writer: false) }

    it "emits no POOL constant" do
      source = generator.emit(descriptor, output: :json, config: config)

      expect(source).not_to include("POOL")
    end

    it "emits no begin/ensure wrap and no checkout/checkin" do
      source = generator.emit(descriptor, output: :json, config: config)

      expect(source).not_to include("POOL.checkout")
      expect(source).not_to include("POOL.checkin")
      expect(source).not_to match(/def serialize_one.*?\bbegin\b/m)
      expect(source).not_to match(/def serialize_many.*?\bbegin\b/m)
    end

    # Byte-identical rollback path — the core acceptance bar for the
    # +pool_writer: false+ knob. A small inline expected-string assertion
    # is sufficient here; the full snapshot tier picks up the long form
    # in S16.3.
    it "emits the pre-pooling shallow_generic source verbatim" do
      source = generator.emit(descriptor, output: :json, config: config)

      expected = <<~RUBY
        # frozen_string_literal: true

        class ShallowGenericSerializer_JSON
          FIELD_INDEX = {id: 0, title: 1}.freeze

          def initialize(descriptor:)
          end

          def serialize_one(record, context: nil, filters: nil)
            filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
            writer = Oj::StringWriter.new(mode: :rails)
            _write_one(record, writer, context, filters)
            result = writer.to_s
            result.chomp!
            result
          end

          def serialize_many(records, context: nil, filters: nil)
            filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
            writer = Oj::StringWriter.new(mode: :rails)
            writer.push_array
            records.each { |r| _write_one(r, writer, context, filters) }
            writer.pop
            result = writer.to_s
            result.chomp!
            result
          end

          def _write_one(record, writer, context, filters)
            if record.is_a?(Hash)
              _write_one_hash(record, writer, context, filters)
            else
              _write_one_object(record, writer, context, filters)
            end
          end

          def _write_one_hash(record, writer, context, filters)
            writer.push_object
            unless filters.drops?(0)
              writer.push_value(record["id"], "id")
            end
            unless filters.drops?(1)
              writer.push_value(record["title"], "title")
            end
            writer.pop
          end

          def _write_one_object(record, writer, context, filters)
            writer.push_object
            unless filters.drops?(0)
              writer.push_value(record.id, "id")
            end
            unless filters.drops?(1)
              writer.push_value(record.title, "title")
            end
            writer.pop
          end
        end
      RUBY

      expect(source).to eq(expected)
    end
  end
end
