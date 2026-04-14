# frozen_string_literal: true

require_relative "compiler/active_record_methods"
require_relative "compiler/object_methods"
require_relative "compiler/method_fields"
require_relative "compiler/associations"

module Panko
  module CodeGen
    # Compiles a {SerializationDescriptor} into a generated class.
    #
    # Takes attribute/association metadata from a descriptor, uses {Emitter}
    # to build unrolled method source strings, and defines them on a new
    # {GeneratedBase} subclass via +module_eval+.
    #
    # All generated methods accept a {FilterMask} (never nil —
    # {FilterMask::EMPTY} for unfiltered calls) so each concern needs
    # only one method instead of separate filtered/unfiltered variants.
    #
    # @example
    #   klass = Compiler.new(MySerializer._descriptor).compile
    #   klass.serialize_one(object: record, writer: writer)
    class Compiler
      include ActiveRecordMethods
      include ObjectMethods
      include MethodFields
      include Associations

      # @param descriptor [Panko::SerializationDescriptor] the descriptor to compile
      def initialize(descriptor)
        @descriptor = descriptor
        @attrs = descriptor.attributes
        @n = @attrs.length
        @method_fields = descriptor.method_fields
        @serializer_type = descriptor.type
        @has_method_fields = !@method_fields.empty?
        @has_one_assocs = descriptor.has_one_associations
        @has_many_assocs = descriptor.has_many_associations
        @has_has_one = !@has_one_assocs.empty?
        @has_has_many = !@has_many_assocs.empty?
      end

      # Compiles the descriptor into a generated class with all methods defined.
      #
      # Only generates methods that require per-serializer unrolling or literal
      # method names. Cold-path and generic methods live on {GeneratedBase}.
      #
      # @return [Class] a GeneratedBase subclass with generated methods
      def compile
        klass = Class.new(GeneratedBase)
        sname = @serializer_type.name || "Anonymous"
        attr_info = @attrs.map(&:name).join(", ")

        klass._ar_writer = ActiveRecordAttributesWriter.new(attrs: @attrs, klass: klass)
        klass._attrs = @attrs

        # AR hot-path: unrolled per-attribute writes (JSON + Hash)
        define_on(klass, gen_write_indexed_cached, "#{sname}::_write_indexed_cached (#{attr_info})")
        define_on(klass, gen_write_indexed_cached_hash, "#{sname}::_write_indexed_cached_hash (#{attr_info})")

        # PORO attribute writes (literal method calls, JSON + Hash)
        define_on(klass, gen_write_plain, "#{sname}::_write_plain (#{attr_info})")
        define_on(klass, gen_write_plain_hash, "#{sname}::_write_plain_hash (#{attr_info})")

        # Method fields (literal method calls on serializer instance)
        if @has_method_fields
          ser = @serializer_type.new(_skip_init: true)
          ser.serialization_context = @descriptor.serializer.serialization_context
          klass._serializer = ser
          mf_info = @method_fields.map(&:name).join(", ")
          define_on(klass, gen_write_method_fields, "#{sname}::_write_method_fields (#{mf_info})")
          define_on(klass, gen_write_method_fields_hash, "#{sname}::_write_method_fields_hash (#{mf_info})")
        end

        # Associations (literal method calls for target resolution)
        if @has_has_one
          klass._has_one_assocs = @has_one_assocs
          klass._ho_static_masks = compute_static_masks(@has_one_assocs)
          ho_info = @has_one_assocs.map(&:name_str).join(", ")
          define_on(klass, gen_write_has_one, "#{sname}::_write_has_one (#{ho_info})")
          define_on(klass, gen_write_has_one_hash, "#{sname}::_write_has_one_hash (#{ho_info})")
        end

        if @has_has_many
          klass._has_many_assocs = @has_many_assocs
          klass._hm_static_masks = compute_static_masks(@has_many_assocs)
          hm_info = @has_many_assocs.map(&:name_str).join(", ")
          define_on(klass, gen_write_has_many, "#{sname}::_write_has_many (#{hm_info})")
          define_on(klass, gen_write_has_many_hash, "#{sname}::_write_has_many_hash (#{hm_info})")
        end

        klass
      end

      private

      # Defines a class method on +klass+ from a Ruby source string
      # and records the source for later inspection via +dump_source+.
      # NOTE: module_eval on trusted internal code only — source is generated
      # from descriptor metadata (attribute names, association names), never
      # from user input.
      def define_on(klass, source, label)
        klass._record_source(label, source)
        klass.module_eval(source, "(panko codegen #{label})", 1)
      end

      # Computes static sub-masks for associations that have built-in filters.
      #
      # @param assocs [Array<Panko::Association>] the associations
      # @return [Array<FilterMask, nil>]
      def compute_static_masks(assocs)
        assocs.map do |assoc|
          sub_canonical = assoc.descriptor.type._descriptor
          Panko::SerializationDescriptor.compute_filter_mask(assoc.descriptor, sub_canonical)
        end
      end
    end
  end
end
