# frozen_string_literal: true

require_relative "compiler/active_record_methods"
require_relative "compiler/object_methods"
require_relative "compiler/dispatch"

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
      # Generates, per serializer:
      #
      # - attribute writers (AR cached, PORO plain, Hash input) — unrolled
      # - +_write_one+ / +_write_one_hash+ — top-level dispatch with the
      #   AR/Hash/PORO branch, inlined method fields, and inlined has_one /
      #   has_many blocks. Absent concerns emit nothing.
      #
      # Cold paths (+_write_indexed_first_pass+, +_write_ar_fallback+) and
      # value helpers live as pre-written methods on {GeneratedBase}.
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

        # Non-AR attribute writes (PORO + Hash input), unrolled.
        define_on(klass, gen_write_plain, "#{sname}::_write_plain (#{attr_info})")
        define_on(klass, gen_write_plain_hash, "#{sname}::_write_plain_hash (#{attr_info})")
        define_on(klass, gen_write_hash, "#{sname}::_write_hash (#{attr_info})")
        define_on(klass, gen_write_hash_hash, "#{sname}::_write_hash_hash (#{attr_info})")

        # Method fields: attach an anonymous subclass of the user's serializer
        # whose +initialize+ sets +@serialization_context+ and +@object+
        # directly. The generated +_write_one+ allocates one instance per
        # record via +@_serializer_class.new(context, object)+, so method
        # fields read their state from freshly-set ivars without a per-call
        # +instance_variable_set+ or cross-call state contamination.
        if @has_method_fields
          klass._serializer_class = Class.new(@serializer_type) do
            def initialize(serialization_context, object)
              @serialization_context = serialization_context
              @object = object
            end
          end
        end

        # Associations: attach metadata + static sub-masks. Calls are inlined
        # into +_write_one+ / +_write_one_hash+.
        if @has_has_one
          klass._has_one_assocs = @has_one_assocs
          klass._ho_static_masks = compute_static_masks(@has_one_assocs)
        end

        if @has_has_many
          klass._has_many_assocs = @has_many_assocs
          klass._hm_static_masks = compute_static_masks(@has_many_assocs)
        end

        # Top-level dispatch: generated per serializer, inlines everything above.
        define_on(klass, gen_write_one, "#{sname}::_write_one")
        define_on(klass, gen_write_one_hash, "#{sname}::_write_one_hash")

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
      # Always returns a {FilterMask} per slot — {FilterMask::EMPTY} when the
      # association has no static filter — so generated code never sees +nil+
      # in this array.
      #
      # @param assocs [Array<Panko::Association>] the associations
      # @return [Array<FilterMask>]
      def compute_static_masks(assocs)
        assocs.map do |assoc|
          sub_canonical = assoc.descriptor.type._descriptor
          Panko::SerializationDescriptor.compute_filter_mask(assoc.descriptor, sub_canonical) ||
            Panko::CodeGen::FilterMask::EMPTY
        end
      end
    end
  end
end
