# frozen_string_literal: true

class ConfigJsonColumnWireFormatSerializer_JSON
  FIELD_INDEX = {id: 0, metadata: 1}.freeze

  def initialize(descriptor:)
  end

  def serialize_one(record, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer, context, filters)
    result = writer.to_s
    result.chomp!
    result
  end

  def serialize_many(records, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = Oj::StringWriter.new(mode: :rails)
    writer.push_array
    records.each { |r| _write_one(r, writer, context, filters) }
    writer.pop
    result = writer.to_s
    result.chomp!
    result
  end

  def _write_one(record, writer, context, filters)
    writer.push_object
    unless filters.drops?(0)
      writer.push_value(record._read_attribute("id"), "id")
    end
    unless filters.drops?(1)
      raw = record.read_attribute_before_type_cast("metadata")
      if raw.is_a?(String) && !raw.empty? && (begin
        Oj.sc_parse(SerializersCodeGen::JSON_NOOP_PARSER, raw, mode: :strict)
        true
      rescue Oj::ParseError, EncodingError
        false
      end)
        writer.push_json(raw, "metadata")
      else
        writer.push_value(record._read_attribute("metadata"), "metadata")
      end
    end
    writer.pop
  end
end
