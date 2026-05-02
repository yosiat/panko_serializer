# frozen_string_literal: true

class RecursiveSelfCommentSerializer_JSON
  FIELD_INDEX = {id: 0, body: 1, replies: 2}.freeze

  def initialize(descriptor:)
    @replies_serializer = self
  end

  def serialize_one(record, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters)
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer, context, filters)
    result = writer.to_s
    result.chomp!
    result
  end

  def serialize_many(records, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters)
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
    unless filters.drops?(2)
      writer.push_array("replies")
      record["replies"].each do |element|
        @replies_serializer._write_one(element, writer, context, filters)
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
      writer.push_value(record.body, "body")
    end
    unless filters.drops?(2)
      writer.push_array("replies")
      record.replies.each do |element|
        @replies_serializer._write_one(element, writer, context, filters)
      end
      writer.pop
    end
    writer.pop
  end
end
