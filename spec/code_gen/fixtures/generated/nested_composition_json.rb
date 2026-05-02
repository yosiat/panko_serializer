# frozen_string_literal: true

class NestedCompositionAuthorSerializer_JSON
  def initialize(descriptor:)
  end

  def serialize_one(record, context: nil, filters: nil)
    raise NotImplementedError if filters
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer, context, filters)
    result = writer.to_s
    result.chomp!
    result
  end

  def serialize_many(records, context: nil, filters: nil)
    raise NotImplementedError if filters
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
    writer.push_value(record["id"], "id")
    writer.push_value(record["name"], "name")
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    writer.push_value(record.id, "id")
    writer.push_value(record.name, "name")
    writer.pop
  end
end

class NestedCompositionCommentSerializer_JSON
  def initialize(descriptor:)
  end

  def serialize_one(record, context: nil, filters: nil)
    raise NotImplementedError if filters
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer, context, filters)
    result = writer.to_s
    result.chomp!
    result
  end

  def serialize_many(records, context: nil, filters: nil)
    raise NotImplementedError if filters
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
    writer.push_value(record["id"], "id")
    writer.push_value(record["body"], "body")
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    writer.push_value(record.id, "id")
    writer.push_value(record.body, "body")
    writer.pop
  end
end

class NestedCompositionPostSerializer_JSON
  def initialize(descriptor:)
    @cb_if_author = descriptor.associations[0].if
    @author_serializer = NestedCompositionAuthorSerializer_JSON.new(descriptor: descriptor.associations[0].descriptor)
    @comments_serializer = NestedCompositionCommentSerializer_JSON.new(descriptor: descriptor.associations[1].descriptor)
  end

  def serialize_one(record, context: nil, filters: nil)
    raise NotImplementedError if filters
    writer = Oj::StringWriter.new(mode: :rails)
    _write_one(record, writer, context, filters)
    result = writer.to_s
    result.chomp!
    result
  end

  def serialize_many(records, context: nil, filters: nil)
    raise NotImplementedError if filters
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
    writer.push_value(record["id"], "id")
    if @cb_if_author.call(record, context)
      value = record["author"]
      if value.nil?
        writer.push_value(nil, "author")
      else
        writer.push_key("author")
        @author_serializer._write_one(value, writer, context, filters)
      end
    end
    writer.push_array("comments")
    record["comments"].each do |element|
      @comments_serializer._write_one(element, writer, context, filters)
    end
    writer.pop
    writer.pop
  end

  def _write_one_object(record, writer, context, filters)
    writer.push_object
    writer.push_value(record.id, "id")
    if @cb_if_author.call(record, context)
      value = record.author
      if value.nil?
        writer.push_value(nil, "author")
      else
        writer.push_key("author")
        @author_serializer._write_one(value, writer, context, filters)
      end
    end
    writer.push_array("comments")
    record.comments.each do |element|
      @comments_serializer._write_one(element, writer, context, filters)
    end
    writer.pop
    writer.pop
  end
end
