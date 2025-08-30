# frozen_string_literal: true

module Panko
  module AttributesWriter
    class << self
      # Initialize all writers upfront for maximum performance
      def initialize_writers
        @active_record_writer = ActiveRecordWriter.new
        @hash_writer = HashWriter.new
        @plain_writer = Plain.new
        @empty_writer = Empty.new
      end

      # Infers the attributes writer from the object type
      def create_attributes_writer(object)
        if active_record_object?(object)
          @active_record_writer
        elsif object.is_a?(Hash)
          @hash_writer
        else
          @plain_writer
        end
      end

      # Creates empty writer for unknown object types
      def create_empty_attributes_writer
        @empty_writer
      end

      private

      def active_record_object?(object)
        return false unless defined?(ActiveRecord::Base)
        object.is_a?(ActiveRecord::Base)
      end
    end

    # Base class for all attribute writers
    class Base
      # Write attributes to the writer using the provided callback
      # @param object [Object] The object to serialize
      # @param attributes [Array<Panko::Attribute>] Array of attributes to serialize
      # @param writer [Object] The writer object (Oj::StringWriter or Panko::ObjectWriter)
      # @param context [Object] Serialization context
      def write_attributes(object, attributes, writer, context = nil)
        attributes.each do |attribute|
          value = read_attribute_value(object, attribute, context)

          # Handle SKIP constant for conditional serialization
          next if value == Panko::Serializer::SKIP

          is_json = attribute.type && type_cast_needed?(attribute.type, value)

          if is_json
            writer.push_json(value, attribute.serialization_name)
          else
            writer.push_value(value, attribute.serialization_name)
          end
        end
      end

      private

      def read_attribute_value(object, attribute, context)
        raise NotImplementedError, "#{self.class} must implement #read_attribute_value"
      end

      def type_cast_needed?(type, value)
        return false unless type && value
        # Basic check - if it's a JSON type or needs special handling
        type.respond_to?(:type) && type.type == :json
      end
    end

    # Empty writer for unknown object types
    class Empty < Base
      private

      def read_attribute_value(object, attribute, context)
        nil
      end
    end
  end
end

# Load individual writer implementations after Base class is defined
require_relative "attributes_writer/plain"
require_relative "attributes_writer/hash"
require_relative "attributes_writer/active_record"

Panko::AttributesWriter.initialize_writers
