# frozen_string_literal: true

require "spec_helper"

describe Panko::CodeGen::GeneratedBase do
  let(:klass) { Class.new(described_class) }
  let(:empty_mask) { Panko::CodeGen::FilterMask::EMPTY }

  describe "._serialize_one" do
    it "wraps _write_one in push_object/pop" do
      writer = Oj::StringWriter.new(mode: :rails)
      written = []

      klass.define_singleton_method(:_write_one) do |_object, w, _filter_mask, _context|
        w.push_value("bar", "foo")
        written << true
      end

      klass._serialize_one({}, writer, nil, empty_mask, nil)

      expect(written).to eq([true])
      expect(Oj.load(writer.to_s)).to eq("foo" => "bar")
    end

    it "passes key to push_object" do
      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object

      klass.define_singleton_method(:_write_one) { |_o, _w, _fm, _ctx| }

      klass._serialize_one({}, writer, "nested", empty_mask, nil)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("nested" => {})
    end

    it "passes filter_mask to _write_one" do
      writer = Oj::StringWriter.new(mode: :rails)
      received_mask = nil

      klass.define_singleton_method(:_write_one) do |_o, _w, fm, _ctx|
        received_mask = fm
      end

      mask = Panko::CodeGen::FilterMask.new(attrs: [true])
      klass._serialize_one({}, writer, nil, mask, nil)

      expect(received_mask).to equal(mask)
    end
  end

  describe "._resolve_type" do
    it "resolves type from types map" do
      attr = Panko::Attribute.create(:name)
      string_type = double("string_type")
      rs = double("record_state", try_additional: false, types: {"name" => string_type})

      klass._resolve_type(attr, rs)

      expect(attr.type).to eq(string_type)
    end

    it "prefers additional_types when try_additional is true" do
      attr = Panko::Attribute.create(:name)
      custom_type = double("custom_type")
      rs = double("record_state",
        try_additional: true,
        additional_types: {"name" => custom_type},
        types: {"name" => double("default_type")})

      klass._resolve_type(attr, rs)

      expect(attr.type).to eq(custom_type)
    end

    it "falls back to types when additional_types has no entry" do
      attr = Panko::Attribute.create(:name)
      default_type = double("default_type")
      rs = double("record_state",
        try_additional: true,
        additional_types: {},
        types: {"name" => default_type})

      klass._resolve_type(attr, rs)

      expect(attr.type).to eq(default_type)
    end
  end

  describe "._write_value" do
    it "writes nil for nil value" do
      attr = Panko::Attribute.create(:name)
      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object

      klass._write_value(attr, nil, writer)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("name" => nil)
    end

    it "uses cached_writer when available" do
      attr = Panko::Attribute.create(:name)
      attr.cached_writer = Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter::StringWriter.new

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object

      klass._write_value(attr, "hello", writer)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("name" => "hello")
    end

    it "uses alias name for serialization key" do
      attr = Panko::Attribute.create(:name, alias_name: :full_name)
      attr.cached_writer = Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter::StringWriter.new

      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object

      klass._write_value(attr, "hello", writer)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("full_name" => "hello")
    end
  end
end
