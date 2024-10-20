# frozen_string_literal: true

module Panko::Impl
  SKIP = Object.new.freeze

  class Serializer
    def initialize(descriptor)
      @descriptor = descriptor
    end

    def serialize_many(objects:, writer:, key: nil)
      writer.push_array(key)

      objects.each do |object|
        serialize_one(object: object, writer: writer)
      end

      writer.pop
    end

    def serialize_one(object:, writer:, key: nil)
      writer.push_object(key)

      write_fields object, writer
      write_method_fields object, writer

      serialize_has_one_association(object, writer)
      serialize_has_many_associations(object, writer)

      writer.pop
    end

    private

    def write_fields(object, writer)
      if @descriptor.attributes_writer.nil?
        @descriptor.attributes_writer = Panko::Impl::AttributesWriter.create(object)
      end

      if @descriptor.attributes_writer.nil?
        Panko._sd_set_writer(@descriptor, object)
        Panko._write_attributes(object, @descriptor, writer)
      else
        @descriptor.attributes_writer.write_attributes(object, @descriptor, writer)
      end
    end

    def serialize_has_one_association(object, writer)
      assocs = @descriptor.has_one_associations
      return if assocs.empty?

      length = assocs.length
      i = 0
      while i < length
        assoc = assocs[i]
        value = object.public_send(assoc.name_sym)

        if value.nil?
          write_value writer, assoc.name_str, nil
        else
          assoc.serializer_writer.serialize_one object: value, writer: writer, key: assoc.name_str
        end
        i += 1
      end
    end

    def serialize_has_many_associations(object, writer)
      assocs = @descriptor.has_many_associations
      return if assocs.empty?

      length = assocs.length
      i = 0
      while i < length
        assoc = assocs[i]
        value = object.public_send(assoc.name_sym)

        if value.nil?
          write_value writer, assoc.name_str, nil
        else
          assoc.serializer_writer.serialize_many objects: value, writer: writer, key: assoc.name_str
        end

        i += 1
      end
    end

    def write_method_fields(object, writer)
      fields = @descriptor.method_fields

      return if fields.empty?

      serializer = @descriptor.serializer
      serializer.instance_variable_set(:@object, object)

      length = fields.length
      i = 0
      while i < length
        method_field = fields[i]
        result = serializer.public_send(method_field.name_sym)

        unless result == SKIP
          key = method_field.name_for_serialization
          write_value(writer, key, result)
        end

        i += 1
      end
    end

    def write_value(writer, key, value)
      writer.push_value(value, key)
    end
  end
end
