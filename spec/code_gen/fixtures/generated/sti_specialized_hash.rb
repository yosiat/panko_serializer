# frozen_string_literal: true

class StiSpecializedSerializer_Hash
  def initialize(descriptor:)
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
    result["vin"] = record._read_attribute("vin")
    result["make"] = record.make
    result
  end
end
