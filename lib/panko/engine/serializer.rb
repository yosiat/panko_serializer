# frozen_string_literal: true

module Panko::Engine
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
      _serialize_many(objects, writer, key)
    end

    def _serialize_many(objects, writer, key = nil)
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

    # Serializes a single object into the writer at the current level.
    # Public API — keyword arguments preserve the existing call interface.
    #
    # @param object [Object] the object to serialize
    # @param writer [Oj::StringWriter, Panko::ObjectWriter] the output writer
    # @param key [String, nil] JSON key under which the object is nested in the output; nil for root
    def serialize_one(object:, writer:, key: nil)
      _serialize_one(object, writer, key)
    end

    # Shared helper for single-object serialization called by serialize_one,
    # serialize_has_one_assocs, and (in the fallback path) _serialize_many.
    # Public by convention so association sub-serializers can call it directly
    # without keyword-argument overhead.
    #
    # @param object [Object] the object to serialize
    # @param writer [Oj::StringWriter, Panko::ObjectWriter] the output writer
    # @param key [String, nil] JSON key under which the object is nested; nil for root
    def _serialize_one(object, writer, key = nil)
      writer.push_object(key)
      write_fields(object, writer)
      write_method_fields(object, writer) unless @method_fields_empty
      serialize_has_one_assocs(object, writer) unless @has_one_empty
      serialize_has_many_assocs(object, writer) unless @has_many_empty
      writer.pop
    end

    private

    def write_fields(object, writer)
      aw = @attributes_writer
      if aw
      else
        aw = Panko::Engine::AttributesWriter.create(object)
        @attributes_writer = aw
        @descriptor.attributes_writer = aw
      end
      aw.write_attributes(object, @descriptor, writer)
    end

    def serialize_has_one_assocs(object, writer)
      @has_one_assocs.each do |assoc|
        # For ActiveRecord objects, bypass the association proxy by calling
        # association().target directly. This skips the stale_target? check
        # and reader method overhead on the hot path.
        # For plain Ruby objects (PORO), fall back to public_send.
        value = if object.respond_to?(:association)
          ar_assoc = object.association(assoc.name_sym)
          ar_assoc.loaded? ? ar_assoc.target : object.public_send(assoc.name_sym)
        else
          object.public_send(assoc.name_sym)
        end

        if value.nil?
          writer.push_value(nil, assoc.name_str)
        else
          assoc.serializer_writer._serialize_one(value, writer, assoc.name_str)
        end
      end
    end

    def serialize_has_many_assocs(object, writer)
      @has_many_assocs.each do |assoc|
        value = object.public_send(assoc.name_sym)

        if value.nil?
          writer.push_value(nil, assoc.name_str)
        else
          assoc.serializer_writer._serialize_many(value, writer, assoc.name_str)
        end
      end
    end

    def write_method_fields(object, writer)
      serializer = @descriptor.serializer
      serializer.instance_variable_set(:@object, object)

      @method_fields.each do |method_field|
        result = serializer.public_send(method_field.name_sym)
        unless result == SKIP
          writer.push_value(result, method_field.name_for_serialization)
        end
      end
    end
  end
end
