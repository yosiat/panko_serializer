# frozen_string_literal: true

class NestedCompositionAuthorSerializer_JSON
  FIELD_INDEX = {id: 0, name: 1}.freeze

  def initialize(descriptor:)
  end

  def serialize_one(record, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer, context, filters)
    result = writer.to_s
    result.chomp!
    result
  end

  def serialize_many(records, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = Oj::StringWriter.new(mode: :rails)
    writer.push_array
    records.each { |r| _write_one(r, writer, context, filters) }
    writer.pop
    result = writer.to_s
    result.chomp!
    result
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
    writer.pop
  end
end

class NestedCompositionCommentSerializer_JSON
  FIELD_INDEX = {id: 0, body: 1}.freeze

  def initialize(descriptor:)
  end

  def serialize_one(record, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer, context, filters)
    result = writer.to_s
    result.chomp!
    result
  end

  def serialize_many(records, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = Oj::StringWriter.new(mode: :rails)
    writer.push_array
    records.each { |r| _write_one(r, writer, context, filters) }
    writer.pop
    result = writer.to_s
    result.chomp!
    result
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
      writer.push_value(record["body"], "body")
    end
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    unless filters.drops?(0)
      writer.push_value(record.id, "id")
    end
    unless filters.drops?(1)
      writer.push_value(record.body, "body")
    end
    writer.pop
  end
end

class NestedCompositionPostSerializer_JSON
  FIELD_INDEX = {id: 0, author: 1, comments: 2}.freeze

  def initialize(descriptor:)
    @cb_if_author = descriptor.associations[0].if
    @author_serializer = NestedCompositionAuthorSerializer_JSON.new(descriptor: descriptor.associations[0].descriptor)
    @comments_serializer = NestedCompositionCommentSerializer_JSON.new(descriptor: descriptor.associations[1].descriptor)
  end

  def serialize_one(record, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer, context, filters)
    result = writer.to_s
    result.chomp!
    result
  end

  def serialize_many(records, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)
    writer = Oj::StringWriter.new(mode: :rails)
    writer.push_array
    records.each { |r| _write_one(r, writer, context, filters) }
    writer.pop
    result = writer.to_s
    result.chomp!
    result
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
      if @cb_if_author.call(record, context)
        value = record["author"]
        if value.nil?
          writer.push_value(nil, "author")
        else
          writer.push_key("author")
          @author_serializer._write_one(value, writer, context, filters.child(:author))
        end
      end
    end
    unless filters.drops?(2)
      child_filter = filters.child(:comments)
      writer.push_array("comments")
      record["comments"].each do |element|
        @comments_serializer._write_one(element, writer, context, child_filter)
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
      if @cb_if_author.call(record, context)
        value = record.author
        if value.nil?
          writer.push_value(nil, "author")
        else
          writer.push_key("author")
          @author_serializer._write_one(value, writer, context, filters.child(:author))
        end
      end
    end
    unless filters.drops?(2)
      child_filter = filters.child(:comments)
      writer.push_array("comments")
      record.comments.each do |element|
        @comments_serializer._write_one(element, writer, context, child_filter)
      end
      writer.pop
    end
    writer.pop
  end
end
