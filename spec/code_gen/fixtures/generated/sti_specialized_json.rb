# frozen_string_literal: true

class StiSpecializedSerializer_JSON
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
    writer.push_object
    writer.push_key("vin")
    writer.push_value(record._read_attribute("vin"))
    writer.push_key("make")
    writer.push_value(record.make)
    writer.pop
  end
end
