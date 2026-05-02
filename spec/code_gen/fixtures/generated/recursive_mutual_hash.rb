# frozen_string_literal: true

class RecursiveMutualItemSerializer_Hash
  FIELD_INDEX = {id: 0, name: 1, subfolder: 2}.freeze

  def initialize(descriptor:, _construct_cache: {})
    _construct_cache[descriptor.__id__] = self
    @subfolder_serializer = (_construct_cache[descriptor.associations[0].descriptor.__id__] ||= RecursiveMutualFolderSerializer_Hash.new(descriptor: descriptor.associations[0].descriptor, _construct_cache: _construct_cache))
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
    unless filters.drops?(2)
      value = record["subfolder"]
      result["subfolder"] = if value.nil?
        nil
      else
        @subfolder_serializer._to_hash(value, context, filters)
      end
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
    unless filters.drops?(2)
      value = record.subfolder
      result["subfolder"] = if value.nil?
        nil
      else
        @subfolder_serializer._to_hash(value, context, filters)
      end
    end
    result
  end
end

class RecursiveMutualFolderSerializer_Hash
  FIELD_INDEX = {id: 0, name: 1, items: 2}.freeze

  def initialize(descriptor:, _construct_cache: {})
    _construct_cache[descriptor.__id__] = self
    @items_serializer = (_construct_cache[descriptor.associations[0].descriptor.__id__] ||= RecursiveMutualItemSerializer_Hash.new(descriptor: descriptor.associations[0].descriptor, _construct_cache: _construct_cache))
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
    unless filters.drops?(2)
      result["items"] = record["items"].map { |element| @items_serializer._to_hash(element, context, filters) }
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
    unless filters.drops?(2)
      result["items"] = record.items.map { |element| @items_serializer._to_hash(element, context, filters) }
    end
    result
  end
end
