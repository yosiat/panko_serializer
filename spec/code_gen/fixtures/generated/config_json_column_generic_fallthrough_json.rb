# frozen_string_literal: true

class ConfigJsonColumnGenericFallthroughSerializer_JSON
  FIELD_INDEX = {id: 0, metadata: 1}.freeze
  POOL = SerializersCodeGen::WritersPool::IsolatedExecutionState.new(:_scg_writer__ConfigJsonColumnGenericFallthroughSerializer_JSON)

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
    if record.is_a?(Hash)
      _write_one_hash(record, writer, context, filters)
    else
      _write_one_object(record, writer, context, filters)
    end
  end

  def _write_one_hash(record, writer, context, filters)
    writer.push_object
    unless filters.drops?(0)
      writer.push_value(record["id"], "id")
    end
    unless filters.drops?(1)
      writer.push_value(record["metadata"], "metadata")
    end
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    unless filters.drops?(0)
      writer.push_value(record.id, "id")
    end
    unless filters.drops?(1)
      writer.push_value(record.metadata, "metadata")
    end
    writer.pop
  end
end
