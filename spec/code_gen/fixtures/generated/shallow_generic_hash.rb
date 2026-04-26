# frozen_string_literal: true

class ShallowGenericSerializer_Hash
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
    if record.is_a?(Hash)
      _to_hash_hash(record, context, filters)
    else
      _to_hash_object(record, context, filters)
    end
  end

  def _to_hash_hash(record, context, filters)
    result = {}
    result["id"] = record["id"]
    result["title"] = record["title"]
    result
  end

  def _to_hash_object(record, context, filters)
    result = {}
    result["id"] = record.id
    result["title"] = record.title
    result
  end
end
