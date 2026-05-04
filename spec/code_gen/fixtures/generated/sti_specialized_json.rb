# frozen_string_literal: true

class StiSpecializedSerializer_JSON
  FIELD_INDEX = {vin: 0, make: 1}.freeze
  POOL = SerializersCodeGen::WritersPool::IsolatedExecutionState.new(:_scg_writer__StiSpecializedSerializer_JSON)

  def initialize(descriptor:)
  end

  def serialize_one(record, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = POOL.checkout
    begin
      _write_one(record, writer, context, filters)
      result = writer.to_s
      result.chomp!
      result
    ensure
      POOL.checkin(writer)
    end
  end

  def serialize_many(records, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = POOL.checkout
    begin
      writer.push_array
      records.each { |r| _write_one(r, writer, context, filters) }
      writer.pop
      result = writer.to_s
      result.chomp!
      result
    ensure
      POOL.checkin(writer)
    end
  end

  def _write_one(record, writer, context, filters)
    writer.push_object
    unless filters.drops?(0)
      writer.push_value(record._read_attribute("vin"), "vin")
    end
    unless filters.drops?(1)
      writer.push_value(record.make, "make")
    end
    writer.pop
  end
end
