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
  # Phase 3 implementation using new AttributesWriter
  module Panko
    def self.serialize_object(object, writer, descriptor)
      # Get the appropriate attributes writer for this object
      attributes_writer = AttributesWriter.create_attributes_writer(object)

      # Write attributes
      attributes_writer.write_attributes(object, descriptor.attributes, writer)

      # Write method fields
      unless descriptor.method_fields.empty?
        method_writer = AttributesWriter.create_attributes_writer(object)
        method_writer.write_attributes(object, descriptor.method_fields, writer)
      end

      # Write associations (to be implemented in Phase 4)
      # TODO: Implement association serialization
    end

    def self.serialize_objects(objects, writer, descriptor)
      objects.each do |object|
        serialize_object(object, writer, descriptor)
      end
    end

    # Type casting method for Phase 2
    def self._type_cast(type_metadata, value)
      TypeCast.type_cast(type_metadata, value)
    end
  end
else
  require "panko/panko_serializer"
end
