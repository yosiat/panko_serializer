# frozen_string_literal: true

class ShallowSpecializedSerializer_JSON
  FIELD_INDEX = {id: 0, title: 1, headline: 2, static: 3, hidden: 4, contextual: 5}.freeze

  def initialize(descriptor:)
    @cb_static = descriptor.method_attributes[0].body
    @cb_hidden = descriptor.method_attributes[1].body
    @cb_contextual = descriptor.method_attributes[2].body
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
      writer.push_value(record._read_attribute("title"), "title")
    end
    unless filters.drops?(2)
      writer.push_value(record.headline, "headline")
    end
    unless filters.drops?(3)
      value = @cb_static.call
      unless value.equal?(SerializersCodeGen::SKIP)
        writer.push_value(value, "static")
      end
    end
    unless filters.drops?(4)
      value = @cb_hidden.call(record)
      unless value.equal?(SerializersCodeGen::SKIP)
        writer.push_value(value, "hidden")
      end
    end
    unless filters.drops?(5)
      value = @cb_contextual.call(record, context)
      unless value.equal?(SerializersCodeGen::SKIP)
        writer.push_value(value, "contextual")
      end
    end
    writer.pop
  end
end
