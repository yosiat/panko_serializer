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

      # Field names can hold any character, so instance variables are named by
      # the Field's position in its Descriptor list, never by its name.
      def serializer_ivar(position)
        "@child_#{position}"
      end

      def variant_serializer_ivar(position, index)
        "#{serializer_ivar(position)}_#{index}"
      end

      def callable_ivar(position)
        "@cb_#{position}"
      end

      def if_guard_ivar(position)
        "@cb_if_#{position}"
      end

      # Names reach generated source only as escaped literals, so a quote or an
      # interpolation in a name cannot change the code.
      def string_literal(name)
        name.to_s.inspect
      end

      def symbol_literal(name)
        name.to_sym.inspect
      end

      PLAIN_METHOD_NAME = /\A[A-Za-z_][A-Za-z0-9_]*[?!]?\z/

      # A name dot syntax cannot parse (+2fa+, +a-b+) is called through +__send__+.
      def method_call(receiver, name)
        return "#{receiver}.#{name}" if PLAIN_METHOD_NAME.match?(name.to_s)
        "#{receiver}.__send__(#{symbol_literal(name)})"
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
