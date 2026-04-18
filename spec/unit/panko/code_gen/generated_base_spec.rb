# frozen_string_literal: true

require "spec_helper"

describe Panko::CodeGen::GeneratedBase do
  let(:klass) { Class.new(described_class) }
  let(:empty_mask) { Panko::CodeGen::FilterMask::EMPTY }

  describe "._serialize_many" do
    it "wraps objects in push_array/pop and delegates each to _write_one" do
      writer = Oj::StringWriter.new(mode: :rails)
      calls = []

      klass.define_singleton_method(:_write_one) do |obj, w, key, _fm, _ctx|
        calls << [obj, key]
        w.push_object(key)
        w.push_value(obj, "v")
        w.pop
      end

      klass._serialize_many([1, 2], writer, nil, empty_mask, nil)

      expect(calls).to eq([[1, nil], [2, nil]])
      expect(Oj.load(writer.to_s)).to eq([{"v" => 1}, {"v" => 2}])
    end

    it "passes key to push_array" do
      writer = Oj::StringWriter.new(mode: :rails)
      writer.push_object

      klass.define_singleton_method(:_write_one) do |_o, w, key, _fm, _ctx|
        w.push_object(key)
        w.pop
      end

      klass._serialize_many([1], writer, "items", empty_mask, nil)
      writer.pop

      expect(Oj.load(writer.to_s)).to eq("items" => [{}])
    end

    it "passes filter_mask to _write_one" do
      writer = Oj::StringWriter.new(mode: :rails)
      received_masks = []

      klass.define_singleton_method(:_write_one) do |_o, w, key, fm, _ctx|
        received_masks << fm
        w.push_object(key)
        w.pop
      end

      mask = Panko::CodeGen::FilterMask.new(attrs: [true])
      klass._serialize_many([1, 2], writer, nil, mask, nil)

      expect(received_masks).to all(equal(mask))
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
