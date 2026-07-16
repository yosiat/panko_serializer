# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # The single home for the emitted-symbol vocabulary — every name that
    # generated source and the emitters that write/read it must agree on.
    # Emitters splice these instead of inline literals so a rename edits
    # one method here (the +_scg_writer__+ → +_panko_writer__+ sweep and
    # the aliased-association filter-key drift both came from a name
    # living as scattered literals).
    module GeneratedNames
      module_function

      # The Generated Class constant for one (Descriptor, mode-suffix)
      # pair, e.g. +"PostSerializer_JSON"+.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @param suffix [String] +"JSON"+ or +"Hash"+
      # @return [String]
      def class_name(descriptor, suffix)
        "#{descriptor.name}_#{suffix}"
      end

      # The Composition ivar holding one Association's nested Generated
      # Class instance, e.g. +"@author_serializer"+. Written by the
      # constructor emit, read by the Association field emitter and the
      # +_release+ emit.
      #
      # @param association [Panko::CodeGen::Association]
      # @return [String]
      def serializer_ivar(association)
        "@#{association.name}_serializer"
      end

      # The hoisted-Callable ivar for one Method Attribute, e.g.
      # +"@cb_slug"+. Written by the constructor emit, invoked at the
      # field-emit site.
      #
      # @param method_attribute [Panko::CodeGen::MethodAttribute]
      # @return [String]
      def callable_ivar(method_attribute)
        "@cb_#{method_attribute.name}"
      end

      # The hoisted +if:+-guard ivar for one Association, e.g.
      # +"@cb_if_author"+.
      #
      # @param association [Panko::CodeGen::Association]
      # @return [String]
      def if_guard_ivar(association)
        "@cb_if_#{association.name}"
      end

      # @return [String] the JSON-mode per-record entry point
      def write_one
        "_write_one"
      end

      # @return [String] the Hash-mode per-record entry point
      def to_hash
        "_to_hash"
      end

      # @return [String] the guarded-Specialized JSON twin (see
      #   +RecordAccess::Specialized+ under +Config#guarded_model+)
      def generic_write_one
        "_generic_write_one"
      end

      # @return [String] the guarded-Specialized Hash twin
      def generic_to_hash
        "_generic_to_hash"
      end

      # @return [String] the above-threshold JSON Hash-record helper
      def write_one_hash
        "_write_one_hash"
      end

      # @return [String] the above-threshold JSON method-dispatch helper
      def write_one_object
        "_write_one_object"
      end

      # @return [String] the above-threshold Hash Hash-record helper
      def to_hash_hash
        "_to_hash_hash"
      end

      # @return [String] the above-threshold Hash method-dispatch helper
      def to_hash_object
        "_to_hash_object"
      end

      # @return [String] the per-class filter-index constant name
      def field_index_const
        "FIELD_INDEX"
      end

      # The fiber-local storage Symbol baked into the emitted +POOL+
      # constant. Derived from the JSON class name so two Generated
      # Classes never share a stack; the prefix keeps the bucket
      # recognizable in +Thread.current+ inspectors.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @return [Symbol]
      def writer_pool_key(descriptor)
        :"_panko_writer__#{class_name(descriptor, "JSON")}"
      end

      # The key one Field occupies in +FIELD_INDEX+ — and therefore the
      # key filter callers address it by: output name for value Fields,
      # declared Source for Associations (matching the sub-filter descent
      # key +Filter#child(:<source>)+ and Panko 0.8.5's alias semantics).
      #
      # @param field [Panko::CodeGen::Attribute,
      #   Panko::CodeGen::MethodAttribute, Panko::CodeGen::Association]
      # @return [Symbol]
      def filter_key(field)
        field.is_a?(Association) ? field.source : field.name
      end
    end
  end
end
