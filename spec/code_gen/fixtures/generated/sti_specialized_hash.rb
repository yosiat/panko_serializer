# frozen_string_literal: true

class StiSpecializedSerializer_Hash
  FIELD_INDEX = {vin: 0, make: 1}.freeze

  def initialize(descriptor:)
  end

  def serialize_one(record, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters)
    _to_hash(record, context, filters)
  end

  def serialize_many(records, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters)
    records.map { |r| _to_hash(r, context, filters) }
  end

  def _to_hash(record, context, filters)
    result = {}
    unless filters.drops?(0)
      result["vin"] = record._read_attribute("vin")
    end
    unless filters.drops?(1)
      result["make"] = record.make
    end
    result
  end
end
