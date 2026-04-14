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
end
