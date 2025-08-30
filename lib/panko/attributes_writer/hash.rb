# frozen_string_literal: true

module Panko
  module AttributesWriter
    # Writer for Hash objects
    class HashWriter < Base
      private

      def read_attribute_value(object, attribute, context)
        # Direct hash lookup using string keys for efficiency
        # Support both string and symbol keys
        value = object[attribute.name_str]

        # Fallback to symbol key if string key not found
        if value.nil? && !object.key?(attribute.name_str)
          value = object[attribute.name_sym]
        end

        value
      end
    end
  end
end
