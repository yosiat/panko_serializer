# frozen_string_literal: true

require_relative "compiler/active_record_methods"
require_relative "compiler/object_methods"
require_relative "compiler/method_fields"
require_relative "compiler/associations"
require_relative "compiler/dispatch"

module Panko
  module CodeGen
    # Compiles a {SerializationDescriptor} into a generated class.
    #
    # Takes attribute/association metadata from a descriptor, uses {Emitter}
    # to build unrolled method source strings, and defines them on a new
    # {GeneratedBase} subclass via +module_eval+.
    #
    # Method generation is organized by concern in separate modules:
    # - {ActiveRecordMethods} — indexed cached, first-pass, fallback paths
    # - {ObjectMethods} — Hash and PORO attribute writes
    # - {MethodFields} — serializer method field writes
    # - {Associations} — has_one and has_many writes
    # - {Dispatch} — top-level _write_one and _serialize_many
    #
    # @example
    #   klass = Compiler.new(MySerializer._descriptor).compile
    #   klass.serialize_one(object: record, writer: writer)
    class Compiler
      include ActiveRecordMethods
      include ObjectMethods
      include MethodFields
      include Associations
      include Dispatch

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
      # @return [Class] a GeneratedBase subclass with generated methods
      def compile
        klass = Class.new(GeneratedBase)

        klass._ar_writer = ActiveRecordAttributesWriter.new(attrs: @attrs, klass: klass)
        klass._attrs = @attrs

        # AR attribute write methods (JSON path)
        define_on(klass, gen_write_indexed_cached, "_write_indexed_cached")
        define_on(klass, gen_write_indexed_cached_filtered, "_write_indexed_cached_filtered")
        define_on(klass, gen_write_indexed_first_pass, "_write_indexed_first_pass")
        define_on(klass, gen_write_indexed_first_pass_filtered, "_write_indexed_first_pass_filtered")
        define_on(klass, gen_write_ar_fallback, "_write_ar_fallback")
        define_on(klass, gen_write_ar_fallback_filtered, "_write_ar_fallback_filtered")

        # AR attribute write methods (Hash path)
        define_on(klass, gen_write_indexed_cached_hash, "_write_indexed_cached_hash")
        define_on(klass, gen_write_indexed_cached_hash_filtered, "_write_indexed_cached_hash_filtered")
        define_on(klass, gen_write_indexed_first_pass_hash, "_write_indexed_first_pass_hash")
        define_on(klass, gen_write_indexed_first_pass_hash_filtered, "_write_indexed_first_pass_hash_filtered")
        define_on(klass, gen_write_ar_fallback_hash, "_write_ar_fallback_hash")
        define_on(klass, gen_write_ar_fallback_hash_filtered, "_write_ar_fallback_hash_filtered")

        # Non-AR attribute write methods (JSON + Hash)
        define_on(klass, gen_write_hash, "_write_hash")
        define_on(klass, gen_write_hash_filtered, "_write_hash_filtered")
        define_on(klass, gen_write_plain, "_write_plain")
        define_on(klass, gen_write_plain_filtered, "_write_plain_filtered")
        define_on(klass, gen_write_hash_hash, "_write_hash_hash")
        define_on(klass, gen_write_hash_hash_filtered, "_write_hash_hash_filtered")
        define_on(klass, gen_write_plain_hash, "_write_plain_hash")
        define_on(klass, gen_write_plain_hash_filtered, "_write_plain_hash_filtered")

        # Method fields
        if @has_method_fields
          ser = @serializer_type.new(_skip_init: true)
          ser.serialization_context = @descriptor.serializer.serialization_context
          klass._serializer = ser
          define_on(klass, gen_write_method_fields, "_write_method_fields")
          define_on(klass, gen_write_method_fields_filtered, "_write_method_fields_filtered")
          define_on(klass, gen_write_method_fields_hash, "_write_method_fields_hash")
          define_on(klass, gen_write_method_fields_hash_filtered, "_write_method_fields_hash_filtered")
        end

        # Associations
        if @has_has_one
          klass._has_one_assocs = @has_one_assocs
          klass._ho_static_masks = compute_static_masks(@has_one_assocs)
          define_on(klass, gen_write_has_one, "_write_has_one")
          define_on(klass, gen_write_has_one_filtered, "_write_has_one_filtered")
          define_on(klass, gen_write_has_one_hash, "_write_has_one_hash")
          define_on(klass, gen_write_has_one_hash_filtered, "_write_has_one_hash_filtered")
        end

        if @has_has_many
          klass._has_many_assocs = @has_many_assocs
          klass._hm_static_masks = compute_static_masks(@has_many_assocs)
          define_on(klass, gen_write_has_many, "_write_has_many")
          define_on(klass, gen_write_has_many_filtered, "_write_has_many_filtered")
          define_on(klass, gen_write_has_many_hash, "_write_has_many_hash")
          define_on(klass, gen_write_has_many_hash_filtered, "_write_has_many_hash_filtered")
        end

        # Top-level dispatch (JSON + Hash)
        define_on(klass, gen_write_one, "_write_one")
        define_on(klass, gen_write_one_hash, "_write_one_hash")
        define_on(klass, gen_serialize_many, "_serialize_many")

        klass
      end

      private

      # Defines a class method on +klass+ from a Ruby source string.
      def define_on(klass, source, label)
        klass.module_eval(source, "(panko codegen #{label})", 1) # rubocop:disable Security/Eval
      end

      # Computes static sub-masks for associations that have built-in filters
      # (e.g. +has_many :foos, only: [:name]+).
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
