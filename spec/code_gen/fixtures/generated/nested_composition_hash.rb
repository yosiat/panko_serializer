# frozen_string_literal: true

class NestedCompositionAuthorSerializer_Hash
  FIELD_INDEX = {id: 0, name: 1}.freeze

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
      result["name"] = record["name"]
    end
    result
  end

  def _to_hash_object(record, context, filters)
    result = {}
    unless filters.drops?(0)
      result["id"] = record.id
    end
    unless filters.drops?(1)
      result["name"] = record.name
    end
    result
  end
end

class NestedCompositionCommentSerializer_Hash
  FIELD_INDEX = {id: 0, body: 1}.freeze

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
    result
  end
end

class NestedCompositionPostSerializer_Hash
  FIELD_INDEX = {id: 0, author: 1, comments: 2}.freeze

  def initialize(descriptor:)
    @cb_if_author = descriptor.associations[0].if
    @author_serializer = NestedCompositionAuthorSerializer_Hash.new(descriptor: descriptor.associations[0].descriptor)
    @comments_serializer = NestedCompositionCommentSerializer_Hash.new(descriptor: descriptor.associations[1].descriptor)
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
      if @cb_if_author.call(record, context)
        value = record["author"]
        result["author"] = if value.nil?
          nil
        else
          @author_serializer._to_hash(value, context, filters)
        end
      end
    end
    unless filters.drops?(2)
      result["comments"] = record["comments"].map { |element| @comments_serializer._to_hash(element, context, filters) }
    end
    result
  end

  def _to_hash_object(record, context, filters)
    result = {}
    unless filters.drops?(0)
      result["id"] = record.id
    end
    unless filters.drops?(1)
      if @cb_if_author.call(record, context)
        value = record.author
        result["author"] = if value.nil?
          nil
        else
          @author_serializer._to_hash(value, context, filters)
        end
      end
    end
    unless filters.drops?(2)
      result["comments"] = record.comments.map { |element| @comments_serializer._to_hash(element, context, filters) }
    end
    result
  end
end
