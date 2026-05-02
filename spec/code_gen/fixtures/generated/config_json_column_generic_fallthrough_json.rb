# frozen_string_literal: true

class ConfigJsonColumnGenericFallthroughSerializer_JSON
  def initialize(descriptor:)
  end

  def serialize_one(record, context: nil, filters: nil)
    raise NotImplementedError if filters
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer, context, filters)
    writer.to_s.chomp
  end

  def serialize_many(records, context: nil, filters: nil)
    raise NotImplementedError if filters
    writer = Oj::StringWriter.new(mode: :rails)
    writer.push_array
    records.each { |r| _write_one(r, writer, context, filters) }
    writer.pop
    writer.to_s.chomp
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
    writer.push_value(record["id"], "id")
    writer.push_value(record["metadata"], "metadata")
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    writer.push_value(record.id, "id")
    writer.push_value(record.metadata, "metadata")
    writer.pop
  end
end
