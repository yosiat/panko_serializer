# frozen_string_literal: true

require_relative "context"
require_relative "values_writer/writer"

module Panko::Impl::AttributesWriter::ActiveRecord
  class Writer
    def write_attributes(object, descriptor, writer)
      attributes_ctx = Context.new(object)
      object_class = object.class

      length = descriptor.attributes.length
      i = 0
      while i < length
        attribute = descriptor.attributes[i]

        attribute.invalidate!(object_class)

        value = attributes_ctx.read_attribute(attribute)

        ValuesWriter.write(writer, attribute, value)

        i += 1
      end
    end
  end
end
