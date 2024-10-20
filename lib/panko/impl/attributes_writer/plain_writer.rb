# frozen_string_literal: true

module Panko::Impl::AttributesWriter
  class PlainWriter
    def write_attributes(object, descriptor, writer)
      descriptor.attributes.each do |attr|
        value = object.public_send(attr.name_sym)
        writer.push_value(value, attr.name_for_serialization)
      end
    end
  end
end
