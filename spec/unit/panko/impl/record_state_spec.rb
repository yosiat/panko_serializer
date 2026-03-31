# frozen_string_literal: true

require "spec_helper"

describe Panko::Impl::AttributesWriter::ActiveRecord::RecordState do
  EMPTY_HASH = Panko::Impl::AttributesWriter::ActiveRecord::EMPTY_HASH

  # Minimal double for an ActiveModel::Attribute entry
  def make_attribute_metadata(value, type)
    meta = double("attribute_metadata")
    allow(meta).to receive(:instance_variable_get).with(:@value_before_type_cast).and_return(value)
    allow(meta).to receive(:instance_variable_get).with(:@type).and_return(type)
    meta
  end

  # Builds a minimal fake attributes_set (like ActiveModel::LazyAttributeSet)
  def make_attributes_set(attributes_hash: nil, types: {}, additional_types: nil, values: {})
    set = double("attributes_set")
    allow(set).to receive(:_panko_attributes_hash).and_return(attributes_hash)
    allow(set).to receive(:_panko_types).and_return(types)
    allow(set).to receive(:_panko_additional_types).and_return(additional_types)
    allow(set).to receive(:_panko_values).and_return(values)
    set
  end

  # Builds a fake non-indexed record (Rails 7.x style)
  def make_plain_record(klass, attributes_hash: nil, types: {}, additional_types: nil, values: {})
    attrs_set = make_attributes_set(
      attributes_hash: attributes_hash,
      types: types,
      additional_types: additional_types,
      values: values
    )
    obj = double("record")
    allow(obj).to receive(:class).and_return(klass)
    allow(obj).to receive(:_panko_attributes).and_return(attrs_set)
    obj
  end

  # Builds a fake IndexedRow-backed object (Rails 8+ style)
  def make_indexed_record(klass, column_indexes:, row:, attributes_hash: nil, types: {}, additional_types: nil)
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
      additional_types: additional_types,
      values: indexed_row
    )
    obj = double("record")
    allow(obj).to receive(:class).and_return(klass)
    allow(obj).to receive(:_panko_attributes).and_return(attrs_set)
    obj
  end

  let(:record_state) { described_class.new }

  describe "#initialize" do
    it "starts with is_indexed_row false" do
      expect(record_state.is_indexed_row).to be false
    end

    it "starts with has_attributes_hash false" do
      expect(record_state.has_attributes_hash).to be false
    end

    it "starts with attributes_hash as EMPTY_HASH" do
      expect(record_state.attributes_hash).to equal(EMPTY_HASH)
    end

    it "starts with nil column_indexes" do
      expect(record_state.column_indexes).to be_nil
    end

    it "starts with nil row" do
      expect(record_state.row).to be_nil
    end
  end

  describe "#setup" do
    context "with a non-indexed (Rails 7.x) record" do
      let(:klass) { Class.new }
      let(:types) { {"name" => double("string_type"), "age" => double("integer_type") } }

      it "returns true on first call (class changed from nil)" do
        obj = make_plain_record(klass, types: types, values: {"name" => "Alice"})
        expect(record_state.setup(obj)).to be true
      end

      it "populates types from attributes_set" do
        obj = make_plain_record(klass, types: types, values: {"name" => "Alice"})
        record_state.setup(obj)
        expect(record_state.types).to equal(types)
      end

      it "sets is_indexed_row to false" do
        obj = make_plain_record(klass, types: types, values: {"name" => "Alice"})
        record_state.setup(obj)
        expect(record_state.is_indexed_row).to be false
      end

      it "sets values for reading via read_attribute" do
        obj = make_plain_record(klass, types: types, values: {"name" => "Alice"})
        record_state.setup(obj)
        expect(record_state.values).to eq("name" => "Alice")
      end

      it "returns false when called again with same class" do
        obj = make_plain_record(klass, types: types, values: {"name" => "Alice"})
        record_state.setup(obj)
        obj2 = make_plain_record(klass, types: types, values: {"name" => "Bob"})
        expect(record_state.setup(obj2)).to be false
      end

      it "returns true when called with a different class" do
        obj = make_plain_record(klass, types: types, values: {"name" => "Alice"})
        record_state.setup(obj)
        other_klass = Class.new
        obj2 = make_plain_record(other_klass, types: types, values: {"name" => "Bob"})
        expect(record_state.setup(obj2)).to be true
      end

      it "sets has_attributes_hash to true when attributes_hash is non-empty" do
        meta = make_attribute_metadata("Alice", double("type"))
        obj = make_plain_record(klass, types: types, attributes_hash: {"name" => meta}, values: {})
        record_state.setup(obj)
        expect(record_state.has_attributes_hash).to be true
      end

      it "sets has_attributes_hash to false when attributes_hash is nil" do
        obj = make_plain_record(klass, types: types, attributes_hash: nil, values: {"name" => "Alice"})
        record_state.setup(obj)
        expect(record_state.has_attributes_hash).to be false
      end

      it "sets try_additional to false when additional_types is nil" do
        obj = make_plain_record(klass, types: types, additional_types: nil, values: {})
        record_state.setup(obj)
        expect(record_state.try_additional).to be false
      end

      it "sets try_additional to true when additional_types is non-empty" do
        obj = make_plain_record(klass, types: types, additional_types: {"custom" => double("custom_type")}, values: {})
        record_state.setup(obj)
        expect(record_state.try_additional).to be true
      end
    end

    context "with an IndexedRow-backed record (Rails 8+)" do
      before do
        skip "IndexedRow not defined in this Rails version" unless Panko::Impl::AttributesWriter::ActiveRecord::PANKO_INDEX_ROW_DEFINED
      end

      let(:klass) { Class.new }
      let(:types) { {"name" => double("string_type") } }
      let(:col_indexes) { {"name" => 0, "age" => 1} }
      let(:row) { ["Alice", 30] }

      it "returns true on first call" do
        obj = make_indexed_record(klass, column_indexes: col_indexes, row: row, types: types)
        expect(record_state.setup(obj)).to be true
      end

      it "sets is_indexed_row to true" do
        obj = make_indexed_record(klass, column_indexes: col_indexes, row: row, types: types)
        record_state.setup(obj)
        expect(record_state.is_indexed_row).to be true
      end

      it "sets column_indexes" do
        obj = make_indexed_record(klass, column_indexes: col_indexes, row: row, types: types)
        record_state.setup(obj)
        expect(record_state.column_indexes).to equal(col_indexes)
      end

      it "sets row" do
        obj = make_indexed_record(klass, column_indexes: col_indexes, row: row, types: types)
        record_state.setup(obj)
        expect(record_state.row).to equal(row)
      end

      it "returns false and only updates row when column_indexes identity matches (fast path)" do
        obj = make_indexed_record(klass, column_indexes: col_indexes, row: row, types: types)
        record_state.setup(obj)

        new_row = ["Bob", 25]
        obj2 = make_indexed_record(klass, column_indexes: col_indexes, row: new_row, types: types)
        # Reuse the same col_indexes object identity to trigger fast path
        attrs_set2 = double("attrs_set2")
        indexed_row2 = double("indexed_row2")
        allow(indexed_row2).to receive(:_panko_column_indexes).and_return(col_indexes)
        allow(indexed_row2).to receive(:_panko_row).and_return(new_row)
        allow(attrs_set2).to receive(:_panko_values).and_return(indexed_row2)
        allow(obj2).to receive(:_panko_attributes).and_return(attrs_set2)

        result = record_state.setup(obj2)
        expect(result).to be false
        expect(record_state.row).to equal(new_row)
      end

      it "returns false (same class) when column_indexes identity differs but same class" do
        obj = make_indexed_record(klass, column_indexes: col_indexes, row: row, types: types)
        record_state.setup(obj)

        new_col_indexes = col_indexes.dup
        new_row = ["Bob", 25]
        obj2 = make_indexed_record(klass, column_indexes: new_col_indexes, row: new_row, types: types)
        expect(record_state.setup(obj2)).to be false
      end
    end
  end

  describe "#read_attribute" do
    let(:klass) { Class.new }
    let(:string_type) { double("string_type") }
    let(:types) { {"name" => string_type} }

    def attr_for(name)
      a = Panko::Attribute.create(name.to_sym)
      a.invalidate!
      a
    end

    it "reads value from values hash when no attributes_hash" do
      obj = make_plain_record(klass, types: types, values: {"name" => "Alice"})
      record_state.setup(obj)
      attribute = attr_for("name")
      expect(record_state.read_attribute(attribute)).to eq("Alice")
    end

    it "assigns type from types hash when type is nil" do
      obj = make_plain_record(klass, types: types, values: {"name" => "Alice"})
      record_state.setup(obj)
      attribute = attr_for("name")
      record_state.read_attribute(attribute)
      expect(attribute.type).to equal(string_type)
    end

    it "returns nil for unknown attribute" do
      obj = make_plain_record(klass, types: types, values: {"name" => "Alice"})
      record_state.setup(obj)
      attribute = attr_for("nonexistent")
      expect(record_state.read_attribute(attribute)).to be_nil
    end

    it "reads value from attributes_hash before values hash" do
      attr_meta_type = double("meta_type")
      meta = make_attribute_metadata("Overridden", attr_meta_type)
      obj = make_plain_record(
        klass,
        types: types,
        attributes_hash: {"name" => meta},
        values: {"name" => "Original"}
      )
      record_state.setup(obj)
      attribute = attr_for("name")
      value = record_state.read_attribute(attribute)
      expect(value).to eq("Overridden")
      expect(attribute.type).to equal(attr_meta_type)
    end

    it "falls back to values hash when attribute_metadata value is nil" do
      meta = make_attribute_metadata(nil, double("meta_type"))
      obj = make_plain_record(
        klass,
        types: types,
        attributes_hash: {"name" => meta},
        values: {"name" => "Fallback"}
      )
      record_state.setup(obj)
      attribute = attr_for("name")
      expect(record_state.read_attribute(attribute)).to eq("Fallback")
    end

    it "uses additional_types when try_additional is true and type is nil" do
      custom_type = double("custom_type")
      additional_types = {"name" => custom_type}
      obj = make_plain_record(klass, types: types, additional_types: additional_types, values: {"name" => "Alice"})
      record_state.setup(obj)
      attribute = attr_for("name")
      record_state.read_attribute(attribute)
      expect(attribute.type).to equal(custom_type)
    end
  end
end
