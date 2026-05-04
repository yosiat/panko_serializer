# frozen_string_literal: true

class RecursiveMutualItemSerializer_JSON
  FIELD_INDEX = {id: 0, name: 1, subfolder: 2}.freeze
  POOL = SerializersCodeGen::WritersPool::IsolatedExecutionState.new(:_scg_writer__RecursiveMutualItemSerializer_JSON)

  def initialize(descriptor:, _construct_cache: {})
    _construct_cache[descriptor.__id__] = self
    @subfolder_serializer = (_construct_cache[descriptor.associations[0].descriptor.__id__] ||= RecursiveMutualFolderSerializer_JSON.new(descriptor: descriptor.associations[0].descriptor, _construct_cache: _construct_cache))
  end

  def serialize_one(record, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = POOL.checkout
    begin
      _write_one(record, writer, context, filters)
      result = writer.to_s
      result.chomp!
      result
    ensure
      POOL.checkin(writer)
    end
  end

  def serialize_many(records, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = POOL.checkout
    begin
      writer.push_array
      records.each { |r| _write_one(r, writer, context, filters) }
      writer.pop
      result = writer.to_s
      result.chomp!
      result
    ensure
      POOL.checkin(writer)
    end
  end

  def _write_one(record, writer, context, filters)
    if record.is_a?(Hash)
      _write_one_hash(record, writer, context, filters)
    else
      _write_one_object(record, writer, context, filters)
    end
  end

  def _write_one_hash(record, writer, context, filters)
    writer.push_object
    unless filters.drops?(0)
      writer.push_value(record["id"], "id")
    end
    unless filters.drops?(1)
      writer.push_value(record["name"], "name")
    end
    unless filters.drops?(2)
      value = record["subfolder"]
      if value.nil?
        writer.push_value(nil, "subfolder")
      else
        writer.push_key("subfolder")
        @subfolder_serializer._write_one(value, writer, context, filters.child(:subfolder, RecursiveMutualFolderSerializer_JSON::FIELD_INDEX))
      end
    end
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    unless filters.drops?(0)
      writer.push_value(record.id, "id")
    end
    unless filters.drops?(1)
      writer.push_value(record.name, "name")
    end
    unless filters.drops?(2)
      value = record.subfolder
      if value.nil?
        writer.push_value(nil, "subfolder")
      else
        writer.push_key("subfolder")
        @subfolder_serializer._write_one(value, writer, context, filters.child(:subfolder, RecursiveMutualFolderSerializer_JSON::FIELD_INDEX))
      end
    end
    writer.pop
  end
end

class RecursiveMutualFolderSerializer_JSON
  FIELD_INDEX = {id: 0, name: 1, items: 2}.freeze
  POOL = SerializersCodeGen::WritersPool::IsolatedExecutionState.new(:_scg_writer__RecursiveMutualFolderSerializer_JSON)

  def initialize(descriptor:, _construct_cache: {})
    _construct_cache[descriptor.__id__] = self
    @items_serializer = (_construct_cache[descriptor.associations[0].descriptor.__id__] ||= RecursiveMutualItemSerializer_JSON.new(descriptor: descriptor.associations[0].descriptor, _construct_cache: _construct_cache))
  end

  def serialize_one(record, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = POOL.checkout
    begin
      _write_one(record, writer, context, filters)
      result = writer.to_s
      result.chomp!
      result
    ensure
      POOL.checkin(writer)
    end
  end

  def serialize_many(records, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = POOL.checkout
    begin
      writer.push_array
      records.each { |r| _write_one(r, writer, context, filters) }
      writer.pop
      result = writer.to_s
      result.chomp!
      result
    ensure
      POOL.checkin(writer)
    end
  end

  def _write_one(record, writer, context, filters)
    if record.is_a?(Hash)
      _write_one_hash(record, writer, context, filters)
    else
      _write_one_object(record, writer, context, filters)
    end
  end

  def _write_one_hash(record, writer, context, filters)
    writer.push_object
    unless filters.drops?(0)
      writer.push_value(record["id"], "id")
    end
    unless filters.drops?(1)
      writer.push_value(record["name"], "name")
    end
    unless filters.drops?(2)
      child_filter = filters.child(:items, RecursiveMutualItemSerializer_JSON::FIELD_INDEX)
      writer.push_array("items")
      record["items"].each do |element|
        @items_serializer._write_one(element, writer, context, child_filter)
      end
      writer.pop
    end
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    unless filters.drops?(0)
      writer.push_value(record.id, "id")
    end
    unless filters.drops?(1)
      writer.push_value(record.name, "name")
    end
    unless filters.drops?(2)
      child_filter = filters.child(:items, RecursiveMutualItemSerializer_JSON::FIELD_INDEX)
      writer.push_array("items")
      record.items.each do |element|
        @items_serializer._write_one(element, writer, context, child_filter)
      end
      writer.pop
    end
    writer.pop
  end
end
