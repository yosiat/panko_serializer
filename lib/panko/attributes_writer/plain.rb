# frozen_string_literal: true

module Panko
  module AttributesWriter
    # Writer for plain Ruby objects
    class Plain < Base
      private

      def read_attribute_value(object, attribute, context)
        # Handle SKIP constant for conditional attributes
        return Serializer::SKIP if attribute.name_str == "SKIP"

        # Use public_send with cached method symbols for fast method dispatch
        if object.respond_to?(attribute.name_sym)
          begin
            object.public_send(attribute.name_sym)
          rescue NoMethodError
            # Edge case: respond_to? returned true but method call failed
            nil
          end
        else
          # Fallback to instance variable access if method doesn't exist
          object.instance_variable_get(attribute.ivar_name)
        end
      end
    end
  end
end
