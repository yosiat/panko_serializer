# frozen_string_literal: true

class ShallowSpecializedSerializer_Hash
  def initialize(descriptor:)
    @cb_static = descriptor.method_attributes[0].body
    @cb_hidden = descriptor.method_attributes[1].body
    @cb_contextual = descriptor.method_attributes[2].body
  end

  def serialize_one(record, context: nil, filters: nil)
    raise NotImplementedError if filters
    _to_hash(record, context, filters)
  end

  def serialize_many(records, context: nil, filters: nil)
    raise NotImplementedError if filters
    records.map { |r| _to_hash(r, context, filters) }
  end

  def _to_hash(record, context, filters)
    result = {}
    result["id"] = record._read_attribute("id")
    result["title"] = record._read_attribute("title")
    result["headline"] = record.headline
    value = @cb_static.call
    unless value.equal?(SerializersCodeGen::SKIP)
      result["static"] = value
    end
    value = @cb_hidden.call(record)
    unless value.equal?(SerializersCodeGen::SKIP)
      result["hidden"] = value
    end
    value = @cb_contextual.call(record, context)
    unless value.equal?(SerializersCodeGen::SKIP)
      result["contextual"] = value
    end
    result
  end
end
