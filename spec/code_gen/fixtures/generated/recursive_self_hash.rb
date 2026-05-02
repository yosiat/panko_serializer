# frozen_string_literal: true

class RecursiveSelfCommentSerializer_Hash
  FIELD_INDEX = {id: 0, body: 1, replies: 2}.freeze

  def initialize(descriptor:)
    @replies_serializer = self
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
      result["id"] = record["id"]
    end
    unless filters.drops?(1)
      result["body"] = record["body"]
    end
    unless filters.drops?(2)
      result["replies"] = record["replies"].map { |element| @replies_serializer._to_hash(element, context, filters) }
    end
    result
  end

  def _to_hash_object(record, context, filters)
    result = {}
    unless filters.drops?(0)
      result["id"] = record.id
    end
    unless filters.drops?(1)
      result["body"] = record.body
    end
    unless filters.drops?(2)
      result["replies"] = record.replies.map { |element| @replies_serializer._to_hash(element, context, filters) }
    end
    result
  end
end
