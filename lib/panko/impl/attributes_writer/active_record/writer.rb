# frozen_string_literal: true

require_relative "context"
require_relative "values_writer/writer"

module Panko::Impl::AttributesWriter::ActiveRecord
  class Writer
    def write_attributes(object, descriptor, writer)
      attributes_ctx = Context.new(object)
      object_class = object.class

      descriptor.attributes.each do |attribute|
        attribute.invalidate!(object_class)

        value = attributes_ctx.read_attribute(attribute)

        ValuesWriter.write(writer, attribute, value)
      end
    end
  end
end
