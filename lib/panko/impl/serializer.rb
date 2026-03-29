# frozen_string_literal: true

module Panko::Impl
  SKIP = Object.new.freeze

  class Serializer
    def initialize(descriptor)
      @descriptor = descriptor
      @has_one_assocs = descriptor.has_one_associations
      @has_many_assocs = descriptor.has_many_associations
      @has_one_empty = @has_one_assocs.empty?
      @has_many_empty = @has_many_assocs.empty?
      @method_fields = descriptor.method_fields
      @method_fields_empty = @method_fields.empty?
      @attributes_writer = nil
    end

    def serialize_many(objects:, writer:, key: nil)
      writer.push_array(key)

      desc = @descriptor
      mf_empty = @method_fields_empty
      ho_empty = @has_one_empty
      hm_empty = @has_many_empty
      aw = @attributes_writer

      if aw && mf_empty && hm_empty
        if ho_empty
          # Ultra-fast: just attributes, no methods/associations
          objects.each do |object|
            writer.push_object
            aw.write_attributes(object, desc, writer)
            writer.pop
          end
        else
          # Attributes + has_one only
          objects.each do |object|
            writer.push_object
            aw.write_attributes(object, desc, writer)
            serialize_has_one_assocs(object, writer)
            writer.pop
          end
        end
      elsif aw
        objects.each do |object|
          writer.push_object
          aw.write_attributes(object, desc, writer)
          write_method_fields(object, writer) unless mf_empty
          serialize_has_one_assocs(object, writer) unless ho_empty
          serialize_has_many_assocs(object, writer) unless hm_empty
          writer.pop
        end
      else
        objects.each do |object|
          writer.push_object
          write_fields(object, writer)
          write_method_fields(object, writer) unless mf_empty
          serialize_has_one_assocs(object, writer) unless ho_empty
          serialize_has_many_assocs(object, writer) unless hm_empty
          writer.pop
        end
      end

      writer.pop
    end

    def serialize_one(object:, writer:, key: nil)
      writer.push_object(key)

      write_fields object, writer
      write_method_fields(object, writer) unless @method_fields_empty
      serialize_has_one_assocs(object, writer) unless @has_one_empty
      serialize_has_many_assocs(object, writer) unless @has_many_empty

      writer.pop
    end

    # Internal fast path: no keyword args, no key (used in serialize_many)
    def _serialize_one(object, writer)
      writer.push_object

      write_fields object, writer
      write_method_fields(object, writer) unless @method_fields_empty
      serialize_has_one_assocs(object, writer) unless @has_one_empty
      serialize_has_many_assocs(object, writer) unless @has_many_empty

      writer.pop
    end

    # Internal with key (used by has_one associations)
    def _serialize_one_with_key(object, writer, key)
      writer.push_object(key)

      write_fields object, writer
      write_method_fields(object, writer) unless @method_fields_empty
      serialize_has_one_assocs(object, writer) unless @has_one_empty
      serialize_has_many_assocs(object, writer) unless @has_many_empty

      writer.pop
    end

    private

    def write_fields(object, writer)
      aw = @attributes_writer
      if aw
        aw.write_attributes(object, @descriptor, writer)
      else
        aw = Panko::Impl::AttributesWriter.create(object)
        @attributes_writer = aw
        @descriptor.attributes_writer = aw
        if aw
          aw.write_attributes(object, @descriptor, writer)
        else
          Panko._sd_set_writer(@descriptor, object)
          Panko._write_attributes(object, @descriptor, writer)
        end
      end
    end

    def serialize_has_one_assocs(object, writer)
      assocs = @has_one_assocs
      length = assocs.length
      i = 0
      while i < length
        assoc = assocs[i]
        # Bypass Rails association proxy: go directly to association target
        # This skips stale_target? check and reader method overhead
        value = object.association(assoc.name_sym).target

        if value.nil?
          writer.push_value(nil, assoc.name_str)
        else
          assoc.serializer_writer._serialize_one_with_key(value, writer, assoc.name_str)
        end
        i += 1
      end
    end

    def serialize_has_many_assocs(object, writer)
      assocs = @has_many_assocs
      length = assocs.length
      i = 0
      while i < length
        assoc = assocs[i]
        value = object.public_send(assoc.name_sym)

        if value.nil?
          writer.push_value(nil, assoc.name_str)
        else
          assoc.serializer_writer.serialize_many objects: value, writer: writer, key: assoc.name_str
        end

        i += 1
      end
    end

    def write_method_fields(object, writer)
      serializer = @descriptor.serializer
      serializer.instance_variable_set(:@object, object)

      fields = @method_fields
      length = fields.length
      i = 0
      while i < length
        method_field = fields[i]
        result = serializer.public_send(method_field.name_sym)

        unless result == SKIP
          writer.push_value(result, method_field.name_for_serialization)
        end

        i += 1
      end
    end
  end
end
