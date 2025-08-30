# frozen_string_literal: true

require "panko/version"
require "panko/attribute"
require "panko/association"
require "panko/time_conversion"
require "panko/type_cast"
require "panko/attributes_writer"
require "panko/serializer"
require "panko/array_serializer"
require "panko/response"
require "panko/serializer_resolver"
require "panko/object_writer"

require "oj"
if ENV["PANKO_PURE_RUBY"] == "true"
  # Phase 4 implementation - Complete Ruby serialization
  module Panko
    def self.serialize_object(object, writer, descriptor, key = nil)
      # Set the appropriate attributes writer for this object type
      set_attributes_writer(descriptor, object)

      # Start object serialization
      writer.push_object(key)

      # Serialize attributes and method fields
      serialize_fields(object, writer, descriptor)

      # Serialize has_one associations
      serialize_has_one_associations(object, writer, descriptor.has_one_associations) unless descriptor.has_one_associations.empty?

      # Serialize has_many associations
      serialize_has_many_associations(object, writer, descriptor.has_many_associations) unless descriptor.has_many_associations.empty?

      # End object serialization
      writer.pop

      nil
    end

    def self.serialize_objects(objects, writer, descriptor, key = nil)
      # Start array serialization
      writer.push_array(key)

      # Convert to array if needed (handles ActiveRecord relations, etc.)
      objects = objects.to_a unless objects.is_a?(Array)

      # Serialize each object
      objects.each do |object|
        serialize_object(object, writer, descriptor)
      end

      # End array serialization
      writer.pop

      nil
    end

    # Type casting method for Phase 2
    def self._type_cast(type_metadata, value)
      TypeCast.type_cast(type_metadata, value)
    end

    class << self
      private

      def set_attributes_writer(descriptor, object)
        # Cache the attributes writer in the descriptor for performance
        descriptor.attributes_writer ||= AttributesWriter.create_attributes_writer(object)
      end

      def serialize_fields(object, writer, descriptor)
        # Serialize regular attributes
        descriptor.attributes_writer.write_attributes(object, descriptor.attributes, writer)

        # Serialize method fields (computed attributes)
        serialize_method_fields(object, writer, descriptor)
      end

      def serialize_method_fields(object, writer, descriptor)
        return if descriptor.method_fields.empty?

        # Set the object context in the serializer instance
        serializer = descriptor.serializer
        serializer.instance_variable_set(:@object, object)

        begin
          descriptor.method_fields.each do |attribute|
            # Call the method on the serializer instance
            result = serializer.public_send(attribute.name_sym)

            # Handle SKIP constant for conditional serialization
            unless result == Panko::Serializer::SKIP
              key = attribute.serialization_name
              writer.push_value(result, key)
            end
          end
        ensure
          # Clean up object reference
          serializer.instance_variable_set(:@object, nil)
        end
      end

      def serialize_has_one_associations(object, writer, associations)
        associations.each do |association|
          # Get the associated object
          value = object.public_send(association.name_sym)

          if value.nil?
            # Write null value for nil associations
            writer.push_value(nil, association.name_str)
          else
            # Recursively serialize the associated object
            serialize_object(value, writer, association.descriptor, association.name_str)
          end
        end
      end

      def serialize_has_many_associations(object, writer, associations)
        associations.each do |association|
          # Get the associated objects
          value = object.public_send(association.name_sym)

          if value.nil?
            # Write null value for nil associations
            writer.push_value(nil, association.name_str)
          else
            # Recursively serialize the associated objects as an array
            serialize_objects(value, writer, association.descriptor, association.name_str)
          end
        end
      end
    end
  end
else
  require "panko/panko_serializer"
end
