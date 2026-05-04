# frozen_string_literal: true

class ConfigJsonColumnHtmlSafeSerializer_JSON
  FIELD_INDEX = {id: 0, metadata: 1}.freeze
  POOL = SerializersCodeGen::WritersPool::IsolatedExecutionState.new(:_scg_writer__ConfigJsonColumnHtmlSafeSerializer_JSON)

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
      writer.push_value(record._read_attribute("id"), "id")
    end
    unless filters.drops?(1)
      writer.push_value(record._read_attribute("metadata"), "metadata")
    end
    writer.pop
  end
end
