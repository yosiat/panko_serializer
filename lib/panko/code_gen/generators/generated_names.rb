# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Names that generated source and the emitters must agree on, kept here
    # so a rename edits one method.
    module GeneratedNames
      module_function

      def class_name(descriptor, suffix)
        "#{descriptor.name}_#{suffix}"
      end

      def serializer_ivar(association)
        "@#{association.name}_serializer"
      end

      def variant_serializer_ivar(association, index)
        "#{serializer_ivar(association)}_#{index}"
      end

      def callable_ivar(method_attribute)
        "@cb_#{method_attribute.name}"
      end

      def if_guard_ivar(association)
        "@cb_if_#{association.name}"
      end

      def write_one
        "_write_one"
      end

      def to_hash
        "_to_hash"
      end

      def generic_write_one
        "_generic_write_one"
      end

      def generic_to_hash
        "_generic_to_hash"
      end

      def write_one_hash
        "_write_one_hash"
      end

      def write_one_object
        "_write_one_object"
      end

      def to_hash_hash
        "_to_hash_hash"
      end

      def to_hash_object
        "_to_hash_object"
      end

      def field_index_const
        "FIELD_INDEX"
      end

      # Associations are keyed by Source, not output name, because nested
      # filters are looked up by Source (+Filter::Indexed#child+).
      def filter_key(field)
        field.is_a?(Association) ? field.source : field.name
      end
    end
  end
end
