# frozen_string_literal: true

class ConfigRootKeyOnSerializer_JSON
  FIELD_INDEX = {id: 0}.freeze

  def initialize(descriptor:)
  end

  def serialize_one(record, context: nil, filters: nil, root_key: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    validate_root_key!(root_key)
    writer = Oj::StringWriter.new(mode: :rails)
    if root_key
      writer.push_object
      writer.push_key(root_key)
    end
    _write_one(record, writer, context, filters)
    writer.pop if root_key
    result = writer.to_s
    result.chomp!
    result
  end

  def serialize_many(records, context: nil, filters: nil, root_key: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    validate_root_key!(root_key)
    writer = Oj::StringWriter.new(mode: :rails)
    writer.push_object if root_key
    writer.push_array(root_key)
    records.each { |r| _write_one(r, writer, context, filters) }
    writer.pop
    writer.pop if root_key
    result = writer.to_s
    result.chomp!
    result
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
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    unless filters.drops?(0)
      writer.push_value(record.id, "id")
    end
    writer.pop
  end

  private def validate_root_key!(root_key)
    return if root_key.nil? || (root_key.is_a?(String) && !root_key.empty?)
    raise ArgumentError, "root_key: must be a non-empty String, got #{root_key.inspect}"
  end
end
