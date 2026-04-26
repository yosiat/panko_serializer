# frozen_string_literal: true

class CommentSerializer_Hash
  def initialize(descriptor:)
    @replies_serializer = self
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
    result["body"] = record["body"]
    result["replies"] = record["replies"].map { |element| @replies_serializer._to_hash(element, context, filters) }
    result
  end

  def _to_hash_object(record, context, filters)
    result = {}
    result["id"] = record.id
    result["body"] = record.body
    result["replies"] = record.replies.map { |element| @replies_serializer._to_hash(element, context, filters) }
    result
  end
end
