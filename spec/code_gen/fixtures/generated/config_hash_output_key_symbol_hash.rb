# frozen_string_literal: true

class ConfigHashOutputKeySymbolSerializer_Hash
  FIELD_INDEX = {id: 0, name: 1}.freeze

  def initialize(descriptor:)
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
    if record.is_a?(Hash)
      _to_hash_hash(record, context, filters)
    else
      _to_hash_object(record, context, filters)
    end
  end

  def _to_hash_hash(record, context, filters)
    result = {}
    unless filters.drops?(0)
      result[:id] = record["id"]
    end
    unless filters.drops?(1)
      result[:name] = record["name"]
    end
    result
  end

  def _to_hash_object(record, context, filters)
    result = {}
    unless filters.drops?(0)
      result[:id] = record.id
    end
    unless filters.drops?(1)
      result[:name] = record.name
    end
    result
  end
end
