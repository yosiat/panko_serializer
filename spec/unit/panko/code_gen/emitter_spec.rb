# frozen_string_literal: true

require "spec_helper"

describe Panko::CodeGen::Emitter do
  # Helper: builds a method from emitter output, defines it on a fresh class,
  # and returns the class so we can call the method with test data.
  # NOTE: module_eval on trusted test code only.
  def build_class_with_method(method_def)
    klass = Class.new(Panko::CodeGen::GeneratedBase)
    klass.module_eval(method_def, "(emitter_spec)", 1)
    klass
  end

  let(:string_writer_instance) do
    Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter::StringWriter.new
  end

  let(:datetime_writer_instance) do
    Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter::DateTimeWriter.new
  end

  let(:include_all) { Panko::CodeGen::FilterMask::INCLUDE_ALL }

  describe "#emit_cached_attr" do
    def build_cached_method(*indices)
      e = described_class.new
      e << "def self.test(row, writer, aw, attr_mask)"
      indices.each { |i| e.emit_cached_attr(i) }
      e << "end"
      build_class_with_method(e.to_source)
    end

    it "writes value directly when writer is nil_safe" do
      klass = build_cached_method(0)
      aw = double(col: [0], key: ["name"], dir: [true], wtr: [string_writer_instance])

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object
      klass.test(["hello"], writer, aw, include_all)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("name" => "hello")
    end

    it "writes nil when value is nil and writer is not nil_safe" do
      klass = build_cached_method(0)
      aw = double(col: [0], key: ["created_at"], dir: [false], wtr: [datetime_writer_instance])

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object
      klass.test([nil], writer, aw, include_all)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("created_at" => nil)
    end

    it "delegates to cached writer when not nil_safe and value is present" do
      klass = build_cached_method(0)
      aw = double(col: [0], key: ["created_at"], dir: [false], wtr: [datetime_writer_instance])

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object
      klass.test(["2024-01-15 10:30:00"], writer, aw, include_all)
      writer.pop

      expect(Oj.load(writer.to_s)["created_at"]).to include("2024-01-15")
    end

    it "unrolls multiple attributes in order" do
      klass = build_cached_method(0, 1)
      aw = double(
        col: [0, 1], key: %w[name title], dir: [true, true],
        wtr: [string_writer_instance, string_writer_instance]
      )

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object
      klass.test(%w[Alice Engineer], writer, aw, include_all)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("name" => "Alice", "title" => "Engineer")
    end

    it "excludes attribute when mask is false" do
      klass = build_cached_method(0, 1)
      aw = double(
        col: [0, 1], key: %w[name title], dir: [true, true],
        wtr: [string_writer_instance, string_writer_instance]
      )

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object
      klass.test(%w[Alice Engineer], writer, aw, [true, false])
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("name" => "Alice")
    end
  end

  describe "#emit_first_pass_attr" do
    def build_first_pass_method(*indices)
      e = described_class.new
      e << "def self.test(attrs, ci, row, rs, writer, attr_mask)"
      indices.each { |i| e.emit_first_pass_attr(i) }
      e << "end"
      build_class_with_method(e.to_source)
    end

    it "resolves type and writes value" do
      attr = Panko::Attribute.create(:name)
      string_type = double("string_type", type: :string)

      klass = build_first_pass_method(0)
      rs = double(
        try_additional: false,
        types: {"name" => string_type},
        additional_types: {}
      )

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object
      klass.test([attr], {"name" => 0}, ["hello"], rs, writer, include_all)
      writer.pop

      expect(attr.type).to eq(string_type)
      expect(Oj.load(writer.to_s)).to eq("name" => "hello")
    end

    it "writes nil when column index is missing" do
      attr = Panko::Attribute.create(:missing)
      klass = build_first_pass_method(0)
      rs = double(try_additional: false, types: {}, additional_types: {})

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object
      klass.test([attr], {}, [], rs, writer, include_all)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("missing" => nil)
    end
  end

  describe "#emit_indexed_with_hash_attr" do
    def build_hash_fallback_method(*indices)
      e = described_class.new
      e << "def self.test(attrs, ci, row, ah, rs, writer, attr_mask)"
      indices.each { |i| e.emit_indexed_with_hash_attr(i) }
      e << "end"
      build_class_with_method(e.to_source)
    end

    it "prefers dirty attribute over indexed row value" do
      attr = Panko::Attribute.create(:name)
      string_type = double("string_type", type: :string)
      am = double("attribute_metadata")
      allow(am).to receive(:instance_variable_get).with(:@value_before_type_cast).and_return("dirty_val")
      allow(am).to receive(:instance_variable_get).with(:@type).and_return(string_type)

      klass = build_hash_fallback_method(0)
      rs = double(try_additional: false, types: {"name" => string_type}, additional_types: {})

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object
      klass.test([attr], {"name" => 0}, ["row_val"], {"name" => am}, rs, writer, include_all)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("name" => "dirty_val")
    end

    it "falls back to indexed row when dirty hash has no entry" do
      attr = Panko::Attribute.create(:name)
      string_type = double("string_type", type: :string)

      klass = build_hash_fallback_method(0)
      rs = double(try_additional: false, types: {"name" => string_type}, additional_types: {})

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object
      klass.test([attr], {"name" => 0}, ["row_val"], {}, rs, writer, include_all)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("name" => "row_val")
    end
  end

  describe "#emit_non_indexed_attr" do
    def build_non_indexed_method(*indices)
      e = described_class.new
      e << "def self.test(attrs, rs, writer, attr_mask)"
      indices.each { |i| e.emit_non_indexed_attr(i) }
      e << "end"
      build_class_with_method(e.to_source)
    end

    it "reads through RecordState and writes via ValuesWriter" do
      attr = Panko::Attribute.create(:name)
      allow(attr).to receive(:type).and_return(nil)

      rs = double("record_state")
      allow(rs).to receive(:read_attribute).with(attr).and_return("from_rs")

      klass = build_non_indexed_method(0)

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object
      klass.test([attr], rs, writer, include_all)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("name" => "from_rs")
    end
  end
end
