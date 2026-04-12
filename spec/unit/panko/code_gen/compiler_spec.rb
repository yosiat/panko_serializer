# frozen_string_literal: true

require "spec_helper"

describe Panko::CodeGen::Compiler do
  before do
    Temping.create(:compiler_test_post) do
      with_columns do |t|
        t.string :title
        t.string :body
        t.integer :author_id
      end
    end
  end

  # Serializer with plain attributes only (no methods, no associations)
  let(:serializer_class) do
    Class.new(Panko::Serializer) { attributes :title, :body, :author_id }
  end

  let(:descriptor) { serializer_class._descriptor }
  let(:compiled) { described_class.new(descriptor).compile }

  describe "#compile" do
    it "returns a GeneratedBase subclass" do
      expect(compiled.superclass).to eq(Panko::CodeGen::GeneratedBase)
    end

    it "defines _write_indexed_cached" do
      expect(compiled).to respond_to(:_write_indexed_cached)
    end

    it "defines _write_indexed_cached_filtered" do
      expect(compiled).to respond_to(:_write_indexed_cached_filtered)
    end

    it "defines _write_indexed_first_pass" do
      expect(compiled).to respond_to(:_write_indexed_first_pass)
    end

    it "defines _write_ar_fallback" do
      expect(compiled).to respond_to(:_write_ar_fallback)
    end

    it "defines _write_ar_fallback_filtered" do
      expect(compiled).to respond_to(:_write_ar_fallback_filtered)
    end

    it "defines _write_one" do
      expect(compiled).to respond_to(:_write_one)
    end
  end

  describe "generated methods with real AR records", if: defined?(::ActiveRecord::Result::IndexedRow) do
    let!(:record) do
      CompilerTestPost.create!(title: "Hello", body: "World", author_id: 42)
    end

    let(:loaded_record) do
      CompilerTestPost.where(id: record.id).first
    end

    describe "_serialize_one (full pipeline)" do
      it "serializes a single AR record to JSON" do
        writer = Oj::StringWriter.new(mode: :rails)
        compiled.serialize_one(object: loaded_record, writer: writer)
        result = Oj.load(writer.to_s)

        expect(result).to eq(
          "title" => "Hello",
          "body" => "World",
          "author_id" => 42
        )
      end
    end

    describe "_serialize_many" do
      let!(:record2) do
        CompilerTestPost.create!(title: "Second", body: "Post", author_id: 99)
      end

      it "serializes an array of AR records to JSON" do
        records = CompilerTestPost.where(id: [record.id, record2.id]).order(:id)

        writer = Oj::StringWriter.new(mode: :rails)
        compiled.serialize_many(objects: records, writer: writer)
        result = Oj.load(writer.to_s)

        expect(result.length).to eq(2)
        expect(result[0]).to eq("title" => "Hello", "body" => "World", "author_id" => 42)
        expect(result[1]).to eq("title" => "Second", "body" => "Post", "author_id" => 99)
      end
    end

    describe "filtered serialization" do
      it "respects FilterMask to exclude attributes" do
        mask = Panko::CodeGen::FilterMask.new(
          attrs: [true, false, true]
        )

        writer = Oj::StringWriter.new(mode: :rails)
        compiled.serialize_one(object: loaded_record, writer: writer, filter_mask: mask)
        result = Oj.load(writer.to_s)

        expect(result).to eq("title" => "Hello", "author_id" => 42)
      end

      it "respects FilterMask to include only specific attributes" do
        mask = Panko::CodeGen::FilterMask.new(
          attrs: [false, true, false]
        )

        writer = Oj::StringWriter.new(mode: :rails)
        compiled.serialize_one(object: loaded_record, writer: writer, filter_mask: mask)
        result = Oj.load(writer.to_s)

        expect(result).to eq("body" => "World")
      end
    end

    describe "correctness vs existing engine" do
      it "produces identical output to Engine::Serializer" do
        records = CompilerTestPost.where(id: record.id)

        # Existing engine
        engine_writer = Oj::StringWriter.new(mode: :rails)
        engine_serializer = Panko::Engine::Serializer.new(descriptor)
        engine_serializer.serialize_many(objects: records, writer: engine_writer)
        engine_result = Oj.load(engine_writer.to_s)

        # Code-gen
        codegen_writer = Oj::StringWriter.new(mode: :rails)
        compiled.serialize_many(objects: records, writer: codegen_writer)
        codegen_result = Oj.load(codegen_writer.to_s)

        expect(codegen_result).to eq(engine_result)
      end
    end
  end
end
