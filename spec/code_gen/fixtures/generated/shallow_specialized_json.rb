# frozen_string_literal: true

class ShallowSpecializedSerializer_JSON
  def initialize(descriptor:)
    @cb_static = descriptor.method_attributes[0].body
    @cb_hidden = descriptor.method_attributes[1].body
    @cb_contextual = descriptor.method_attributes[2].body
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
    writer.push_value(record._read_attribute("id"), "id")
    writer.push_value(record._read_attribute("title"), "title")
    writer.push_value(record.headline, "headline")
    value = @cb_static.call
    unless value.equal?(SerializersCodeGen::SKIP)
      writer.push_value(value, "static")
    end
    value = @cb_hidden.call(record)
    unless value.equal?(SerializersCodeGen::SKIP)
      writer.push_value(value, "hidden")
    end
    value = @cb_contextual.call(record, context)
    unless value.equal?(SerializersCodeGen::SKIP)
      writer.push_value(value, "contextual")
    end
    writer.pop
  end
end
