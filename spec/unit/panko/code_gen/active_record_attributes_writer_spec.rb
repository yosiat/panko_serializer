# frozen_string_literal: true

require "spec_helper"

describe Panko::CodeGen::ActiveRecordAttributesWriter do
  # Reuse record_state_spec's double-building helpers
  def make_attributes_set(attributes_hash: nil, types: {}, additional_types: nil, values: {})
    set = double("attributes_set")
    allow(set).to receive(:_panko_attributes_hash).and_return(attributes_hash)
    allow(set).to receive(:_panko_types).and_return(types)
    allow(set).to receive(:_panko_additional_types).and_return(additional_types)
    allow(set).to receive(:_panko_values).and_return(values)
    set
  end

  def make_indexed_record(klass, column_indexes:, row:, attributes_hash: nil, types: {})
    indexed_row = double("indexed_row")
    allow(indexed_row).to receive(:is_a?).with(anything).and_return(false)
    if defined?(::ActiveRecord::Result::IndexedRow)
      allow(indexed_row).to receive(:is_a?).with(::ActiveRecord::Result::IndexedRow).and_return(true)
    end
    allow(indexed_row).to receive(:_panko_column_indexes).and_return(column_indexes)
    allow(indexed_row).to receive(:_panko_row).and_return(row)

    attrs_set = make_attributes_set(
      attributes_hash: attributes_hash,
      types: types,
      values: indexed_row
    )
    obj = double("record")
    allow(obj).to receive(:class).and_return(klass)
    allow(obj).to receive(:_panko_attributes).and_return(attrs_set)
    obj
  end

  let(:klass) { Class.new(Panko::CodeGen::GeneratedBase) }
  let(:attrs) { [Panko::Attribute.create(:name), Panko::Attribute.create(:title)] }
  let(:writer_instance) { described_class.new(attrs: attrs, klass: klass) }

  describe "#initialize" do
    it "starts with caches not ready" do
      expect(writer_instance.caches_ready?).to be false
    end

    it "starts with nil cache arrays" do
      expect(writer_instance.col).to be_nil
      expect(writer_instance.key).to be_nil
      expect(writer_instance.wtr).to be_nil
      expect(writer_instance.dir).to be_nil
    end

    it "exposes the attrs array" do
      expect(writer_instance.attrs).to eq(attrs)
    end
  end

  describe "#record_state" do
    it "returns a RecordState instance" do
      rs = writer_instance.record_state
      expect(rs).to be_a(Panko::Engine::AttributesWriter::ActiveRecord::RecordState)
    end

    it "returns the same instance on subsequent calls (thread-local)" do
      rs1 = writer_instance.record_state
      rs2 = writer_instance.record_state
      expect(rs1).to equal(rs2)
    end
  end

  # IndexedRow is only available on Rails 8+
  indexed_row_available = defined?(::ActiveRecord::Result::IndexedRow)

  describe "#build_caches!", if: indexed_row_available do
    let(:record_class) { Class.new }
    let(:column_indexes) { {"name" => 0, "title" => 1} }
    let(:row) { ["hello", "world"] }
    let(:string_type) { double("string_type", type: :string) }
    let(:types) { {"name" => string_type, "title" => string_type} }

    before do
      attrs[0].type = string_type
      attrs[0].cached_writer = Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter::StringWriter.new
      attrs[1].type = string_type
      attrs[1].cached_writer = Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter::StringWriter.new
    end

    it "builds parallel cache arrays" do
      rs = writer_instance.record_state
      record = make_indexed_record(record_class, column_indexes: column_indexes, row: row, types: types)
      rs.setup(record)

      writer_instance.build_caches!(rs)

      expect(writer_instance.caches_ready?).to be true
      expect(writer_instance.col).to eq([0, 1])
      expect(writer_instance.key).to eq(%w[name title])
      expect(writer_instance.wtr.length).to eq(2)
      expect(writer_instance.dir).to eq([true, true])
    end

    it "is idempotent" do
      rs = writer_instance.record_state
      record = make_indexed_record(record_class, column_indexes: column_indexes, row: row, types: types)
      rs.setup(record)

      writer_instance.build_caches!(rs)
      first_col = writer_instance.col

      writer_instance.build_caches!(rs)
      expect(writer_instance.col).to equal(first_col)
    end
  end

  describe "#write", if: indexed_row_available do
    let(:record_class) { Class.new }
    let(:column_indexes) { {"name" => 0, "title" => 1} }
    let(:string_type) { double("string_type", type: :string) }
    let(:types) { {"name" => string_type, "title" => string_type} }

    context "when caches are not ready (first pass)" do
      it "delegates to klass._write_indexed_first_pass" do
        row = ["hello", "world"]
        record = make_indexed_record(record_class, column_indexes: column_indexes, row: row, types: types)

        first_pass_called = false
        klass.define_singleton_method(:_write_indexed_first_pass) do |aw, rs, writer, attr_mask|
          first_pass_called = true
        end

        writer = Oj::StringWriter.new(mode: :rails)
        writer_instance.write(record, writer, Panko::CodeGen::FilterMask::EMPTY)

        expect(first_pass_called).to be true
      end
    end

    context "when caches are ready" do
      before do
        attrs[0].type = string_type
        attrs[0].cached_writer = Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter::StringWriter.new
        attrs[1].type = string_type
        attrs[1].cached_writer = Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter::StringWriter.new

        row = ["hello", "world"]
        record = make_indexed_record(record_class, column_indexes: column_indexes, row: row, types: types)
        rs = writer_instance.record_state
        rs.setup(record)
        writer_instance.build_caches!(rs)
      end

      it "delegates to klass._write_indexed_cached with INCLUDE_ALL when unfiltered" do
        row = ["foo", "bar"]
        record = make_indexed_record(record_class, column_indexes: column_indexes, row: row, types: types)

        cached_called_with = nil
        klass.define_singleton_method(:_write_indexed_cached) do |r, w, mask|
          cached_called_with = [r, mask]
        end

        writer = Oj::StringWriter.new(mode: :rails)
        writer_instance.write(record, writer, Panko::CodeGen::FilterMask::EMPTY)

        expect(cached_called_with).to eq([row, Panko::CodeGen::FilterMask::INCLUDE_ALL])
      end

      it "delegates to klass._write_indexed_cached with real mask when filtered" do
        row = ["foo", "bar"]
        record = make_indexed_record(record_class, column_indexes: column_indexes, row: row, types: types)

        cached_called_with = nil
        klass.define_singleton_method(:_write_indexed_cached) do |r, w, mask|
          cached_called_with = [r, mask]
        end

        mask = Panko::CodeGen::FilterMask.new(attrs: [true, false])
        writer = Oj::StringWriter.new(mode: :rails)
        writer_instance.write(record, writer, mask)

        expect(cached_called_with).to eq([row, [true, false]])
      end
    end
  end
end
