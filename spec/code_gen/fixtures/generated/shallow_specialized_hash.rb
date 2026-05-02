# frozen_string_literal: true

class ShallowSpecializedSerializer_Hash
  FIELD_INDEX = {id: 0, title: 1, headline: 2, static: 3, hidden: 4, contextual: 5}.freeze

  def initialize(descriptor:)
    @cb_static = descriptor.method_attributes[0].body
    @cb_hidden = descriptor.method_attributes[1].body
    @cb_contextual = descriptor.method_attributes[2].body
  end

  def serialize_one(record, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    _to_hash(record, context, filters)
  end

  def serialize_many(records, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    records.map { |r| _to_hash(r, context, filters) }
  end

  def _to_hash(record, context, filters)
    result = {}
    unless filters.drops?(0)
      result["id"] = record._read_attribute("id")
    end
    unless filters.drops?(1)
      result["title"] = record._read_attribute("title")
    end
    unless filters.drops?(2)
      result["headline"] = record.headline
    end
    unless filters.drops?(3)
      value = @cb_static.call
      unless value.equal?(SerializersCodeGen::SKIP)
        result["static"] = value
      end
    end
    unless filters.drops?(4)
      value = @cb_hidden.call(record)
      unless value.equal?(SerializersCodeGen::SKIP)
        result["hidden"] = value
      end
    end
    unless filters.drops?(5)
      value = @cb_contextual.call(record, context)
      unless value.equal?(SerializersCodeGen::SKIP)
        result["contextual"] = value
      end
    end
    result
  end
end
