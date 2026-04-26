# frozen_string_literal: true

class NestedCompositionAuthorSerializer_Hash
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
    result["name"] = record["name"]
    result
  end

  def _to_hash_object(record, context, filters)
    result = {}
    result["id"] = record.id
    result["name"] = record.name
    result
  end
end

class NestedCompositionCommentSerializer_Hash
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
    result["body"] = record["body"]
    result
  end

  def _to_hash_object(record, context, filters)
    result = {}
    result["id"] = record.id
    result["body"] = record.body
    result
  end
end

class NestedCompositionPostSerializer_Hash
  def initialize(descriptor:)
    @cb_if_author = descriptor.associations[0].if
    @author_serializer = NestedCompositionAuthorSerializer_Hash.new(descriptor: descriptor.associations[0].descriptor)
    @comments_serializer = NestedCompositionCommentSerializer_Hash.new(descriptor: descriptor.associations[1].descriptor)
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
    if @cb_if_author.call(record, context)
      value = record["author"]
      result["author"] = if value.nil?
        nil
      else
        @author_serializer._to_hash(value, context, filters)
      end
    end
    result["comments"] = record["comments"].map { |element| @comments_serializer._to_hash(element, context, filters) }
    result
  end

  def _to_hash_object(record, context, filters)
    result = {}
    result["id"] = record.id
    if @cb_if_author.call(record, context)
      value = record.author
      result["author"] = if value.nil?
        nil
      else
        @author_serializer._to_hash(value, context, filters)
      end
    end
    result["comments"] = record.comments.map { |element| @comments_serializer._to_hash(element, context, filters) }
    result
  end
end
