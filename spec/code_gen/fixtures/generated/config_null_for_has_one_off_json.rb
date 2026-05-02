# frozen_string_literal: true

class ConfigNullForHasOneOffInnerSerializer_JSON
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
    writer.push_value(record["name"], "name")
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    writer.push_value(record.id, "id")
    writer.push_value(record.name, "name")
    writer.pop
  end
end

class ConfigNullForHasOneOffSerializer_JSON
  def initialize(descriptor:)
    @inner_serializer = ConfigNullForHasOneOffInnerSerializer_JSON.new(descriptor: descriptor.associations[0].descriptor)
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
    value = record["inner"]
    unless value.nil?
      writer.push_key("inner")
      @inner_serializer._write_one(value, writer, context, filters)
    end
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    writer.push_value(record.id, "id")
    value = record.inner
    unless value.nil?
      writer.push_key("inner")
      @inner_serializer._write_one(value, writer, context, filters)
    end
    writer.pop
  end
end
