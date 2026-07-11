# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

RSpec.describe "Specialized guarded-model emit" do
  let(:generator) { Panko::CodeGen::Generator.new }
  let(:guarded_config) { Panko::CodeGen::Config.new(guarded_model: true) }
  let(:unguarded_config) { Panko::CodeGen::Config.new }

  let(:descriptor) do
    Panko::CodeGen::Descriptor.new(
      name: "GuardedPlainPostSerializer",
      model: PlainPost,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :title, source: :title)
      ],
      method_attributes: [],
      associations: []
    )
  end

  describe "emitted source" do
    it "prepends the instance_of? guard delegating to the generic twin (json)" do
      source = generator.emit(descriptor, output: :json, config: guarded_config)

      expect(source).to include(
        "return _generic_write_one(record, writer, context, scope, filters) unless record.instance_of?(::PlainPost)"
      )
      expect(source).to include("def _generic_write_one(record, writer, context, scope, filters)")
      expect(source).to include("if record.is_a?(Hash)")
    end

    it "prepends the instance_of? guard delegating to the generic twin (hash)" do
      source = generator.emit(descriptor, output: :hash, config: guarded_config)

      expect(source).to include(
        "return _generic_to_hash(record, context, scope, filters) unless record.instance_of?(::PlainPost)"
      )
      expect(source).to include("def _generic_to_hash(record, context, scope, filters)")
    end

    it "emits no guard and no twin without the flag" do
      source = generator.emit(descriptor, output: :json, config: unguarded_config)

      expect(source).not_to include("instance_of?")
      expect(source).not_to include("_generic_write_one")
    end

    it "raises CompileError for an anonymous Model (the guard needs a constant path)" do
      anonymous = Class.new(::ActiveRecord::Base) { self.table_name = "posts" }
      anonymous_descriptor = descriptor.with(model: anonymous)

      expect {
        generator.emit(anonymous_descriptor, output: :json, config: guarded_config)
      }.to raise_error(Panko::CodeGen::CompileError, /guarded_model requires a named Model class/)
    end
  end

  describe "runtime delegation" do
    let(:matching_record) { PlainPost.new(id: 1, title: "hi") }
    let(:hash_record) { {"id" => 1, "title" => "hi"} }
    let(:poro_record) { Struct.new(:id, :title).new(1, "hi") }

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated) do
          Panko::CodeGen.compile(descriptor, output: mode, config: guarded_config).new(descriptor: descriptor)
        end

        def normalized(output, mode)
          (mode == :json) ? Oj.load(output) : output
        end

        it "serializes a matching record through the specialized body" do
          result = normalized(generated.serialize_one(matching_record), mode)
          expect(result).to eq("id" => 1, "title" => "hi")
        end

        it "serializes a Hash record through the generic twin" do
          result = normalized(generated.serialize_one(hash_record), mode)
          expect(result).to eq("id" => 1, "title" => "hi")
        end

        it "serializes a PORO through the generic twin" do
          result = normalized(generated.serialize_one(poro_record), mode)
          expect(result).to eq("id" => 1, "title" => "hi")
        end

        it "serializes a mixed batch — guard evaluated per record" do
          result = generated.serialize_many([matching_record, hash_record, poro_record])
          result = Oj.load(result) if mode == :json
          expect(result).to eq(Array.new(3) { {"id" => 1, "title" => "hi"} })
        end
      end
    end
  end
end
