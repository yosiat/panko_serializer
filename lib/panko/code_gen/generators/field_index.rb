# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Indexes are written into each Field's +filters.drops?(N)+ check, so
    # filtering a Field costs one Array lookup instead of a Hash lookup.
    module FieldIndex
      module_function

      # Look indexes up by +GeneratedNames.filter_key+, never by position:
      # {FieldWalk} emits Associations before Method Attributes.
      def build(descriptor)
        index = {}
        i = 0
        fields = descriptor.attributes + descriptor.method_attributes + descriptor.associations
        fields.each do |field|
          index[GeneratedNames.filter_key(field)] = i
          i += 1
        end
        index
      end

      # Ruby 3.4+ +Hash#inspect+ quotes a Symbol key that is not an identifier (+"2fa": 0+).
      def to_hash_literal(field_index)
        field_index.inspect
      end
    end
  end
end
