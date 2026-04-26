# frozen_string_literal: true

class RecursiveMutualItemSerializer_JSON
  def initialize(descriptor:, _construct_cache: {})
    _construct_cache[descriptor.__id__] = self
    @subfolder_serializer = (_construct_cache[descriptor.associations[0].descriptor.__id__] ||= RecursiveMutualFolderSerializer_JSON.new(descriptor: descriptor.associations[0].descriptor, _construct_cache: _construct_cache))
  end

  def serialize_one(record, context: nil, filters: nil)
    raise NotImplementedError if filters
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer, context, filters)
    writer.to_s.chomp
  end

  def serialize_many(records, context: nil, filters: nil)
    raise NotImplementedError if filters
    writer = Oj::StringWriter.new(mode: :rails)
    writer.push_array
    records.each { |r| _write_one(r, writer, context, filters) }
    writer.pop
    writer.to_s.chomp
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
    writer.push_key("id")
    writer.push_value(record["id"])
    writer.push_key("name")
    writer.push_value(record["name"])
    value = record["subfolder"]
    writer.push_key("subfolder")
    if value.nil?
      writer.push_value(nil)
    else
      @subfolder_serializer._write_one(value, writer, context, filters)
    end
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    writer.push_key("id")
    writer.push_value(record.id)
    writer.push_key("name")
    writer.push_value(record.name)
    value = record.subfolder
    writer.push_key("subfolder")
    if value.nil?
      writer.push_value(nil)
    else
      @subfolder_serializer._write_one(value, writer, context, filters)
    end
    writer.pop
  end
end

class RecursiveMutualFolderSerializer_JSON
  def initialize(descriptor:, _construct_cache: {})
    _construct_cache[descriptor.__id__] = self
    @items_serializer = (_construct_cache[descriptor.associations[0].descriptor.__id__] ||= RecursiveMutualItemSerializer_JSON.new(descriptor: descriptor.associations[0].descriptor, _construct_cache: _construct_cache))
  end

  def serialize_one(record, context: nil, filters: nil)
    raise NotImplementedError if filters
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer, context, filters)
    writer.to_s.chomp
  end

  def serialize_many(records, context: nil, filters: nil)
    raise NotImplementedError if filters
    writer = Oj::StringWriter.new(mode: :rails)
    writer.push_array
    records.each { |r| _write_one(r, writer, context, filters) }
    writer.pop
    writer.to_s.chomp
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
    writer.push_key("id")
    writer.push_value(record["id"])
    writer.push_key("name")
    writer.push_value(record["name"])
    writer.push_key("items")
    writer.push_array
    record["items"].each do |element|
      @items_serializer._write_one(element, writer, context, filters)
    end
    writer.pop
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    writer.push_key("id")
    writer.push_value(record.id)
    writer.push_key("name")
    writer.push_value(record.name)
    writer.push_key("items")
    writer.push_array
    record.items.each do |element|
      @items_serializer._write_one(element, writer, context, filters)
    end
    writer.pop
    writer.pop
  end
end
