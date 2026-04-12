# frozen_string_literal: true

module Panko
  module CodeGen
    # Compiles a {SerializationDescriptor} into a generated class.
    #
    # Takes attribute/association metadata from a descriptor, uses {Emitter}
    # to build unrolled method source strings, and defines them on a new
    # {GeneratedBase} subclass via +module_eval+.
    #
    # @example
    #   klass = Compiler.new(MySerializer._descriptor).compile
    #   klass.serialize_one(object: record, writer: writer)
    class Compiler
      # @param descriptor [Panko::SerializationDescriptor] the descriptor to compile
      def initialize(descriptor)
        @attrs = descriptor.attributes
        @n = @attrs.length
      end

      # Compiles the descriptor into a generated class with all methods defined.
      #
      # @return [Class] a GeneratedBase subclass with generated methods
      def compile
        klass = Class.new(GeneratedBase)

        ar_writer = ActiveRecordAttributesWriter.new(attrs: @attrs, klass: klass)
        klass.instance_variable_set(:@_ar_writer, ar_writer)

        define_on(klass, gen_write_indexed_cached, "_write_indexed_cached")
        define_on(klass, gen_write_indexed_cached_filtered, "_write_indexed_cached_filtered")
        define_on(klass, gen_write_indexed_first_pass, "_write_indexed_first_pass")
        define_on(klass, gen_write_indexed_first_pass_filtered, "_write_indexed_first_pass_filtered")
        define_on(klass, gen_write_ar_fallback, "_write_ar_fallback")
        define_on(klass, gen_write_ar_fallback_filtered, "_write_ar_fallback_filtered")
        define_on(klass, gen_write_one, "_write_one")

        klass
      end

      private

      # Defines a class method on +klass+ from a Ruby source string.
      # Uses +module_eval+ — the standard Ruby metaprogramming mechanism
      # for defining methods from source at class-load time.
      # All source strings are generated internally by the Compiler —
      # no external input is ever evaluated.
      def define_on(klass, source, label)
        klass.module_eval(source, "(panko codegen #{label})", 1) # rubocop:disable Security/Eval
      end

      # Generates +_write_indexed_cached+ — unrolled hot path.
      # Reads from +@_ar_writer+ parallel caches, no filter.
      def gen_write_indexed_cached
        e = Emitter.new
        e << "def self._write_indexed_cached(row, writer)"
        e << "aw = @_ar_writer"
        @n.times { |i| e.emit_cached_attr(i) }
        e << "end"
        e.to_source
      end

      # Generates +_write_indexed_cached_filtered+ — unrolled hot path with filter guards.
      def gen_write_indexed_cached_filtered
        e = Emitter.new
        e << "def self._write_indexed_cached_filtered(row, writer, attr_mask)"
        e << "aw = @_ar_writer"
        @n.times { |i| e.emit_cached_attr_filtered(i) }
        e << "end"
        e.to_source
      end

      # Generates +_write_indexed_first_pass+ — unrolled type resolution.
      # Runs once per attribute set, then caches are built.
      def gen_write_indexed_first_pass
        e = Emitter.new
        e << "def self._write_indexed_first_pass(aw, rs, writer)"
        e << "ci = rs.column_indexes"
        e << "row = rs.row"
        e << "attrs = aw.attrs"
        @n.times { |i| e.emit_first_pass_attr(i) }
        e << "end"
        e.to_source
      end

      # Generates +_write_indexed_first_pass_filtered+ — unrolled type resolution
      # with filter guards. Resolves types for all attributes (needed for cache
      # building) but only writes filtered ones.
      def gen_write_indexed_first_pass_filtered
        e = Emitter.new
        e << "def self._write_indexed_first_pass_filtered(aw, rs, writer, attr_mask)"
        e << "ci = rs.column_indexes"
        e << "row = rs.row"
        e << "attrs = aw.attrs"
        @n.times { |i| e.emit_first_pass_attr_filtered(i) }
        e << "end"
        e.to_source
      end

      # Generates +_write_ar_fallback+ — unrolled fallback for dirty attrs
      # or non-indexed (Rails 7.x) records.
      def gen_write_ar_fallback
        e = Emitter.new
        e << "def self._write_ar_fallback(aw, rs, writer)"
        e << "attrs = aw.attrs"
        e << "if rs.is_indexed_row"
        e << "  ci = rs.column_indexes"
        e << "  row = rs.row"
        e << "  ah = rs.attributes_hash"
        @n.times { |i| e.emit_indexed_with_hash_attr(i) }
        e << "else"
        @n.times { |i| e.emit_non_indexed_attr(i) }
        e << "end"
        e << "end"
        e.to_source
      end

      # Generates +_write_ar_fallback_filtered+ — filtered variant.
      def gen_write_ar_fallback_filtered
        e = Emitter.new
        e << "def self._write_ar_fallback_filtered(aw, rs, writer, attr_mask)"
        e << "attrs = aw.attrs"
        e << "if rs.is_indexed_row"
        e << "  ci = rs.column_indexes"
        e << "  row = rs.row"
        e << "  ah = rs.attributes_hash"
        @n.times { |i| e.emit_indexed_with_hash_attr_filtered(i) }
        e << "else"
        @n.times { |i| e.emit_non_indexed_attr_filtered(i) }
        e << "end"
        e << "end"
        e.to_source
      end

      # Generates +_write_one+ — object-type dispatch.
      # Handles AR objects only for now. Hash/PORO support added in later commits.
      def gen_write_one
        <<~RUBY
          def self._write_one(object, writer, filter_mask)
            if object.is_a?(ActiveRecord::Base)
              @_ar_writer.write(object, writer, filter_mask)
            elsif object.is_a?(Hash)
              raise NotImplementedError, "Hash serialization not yet implemented in CodeGen"
            else
              raise NotImplementedError, "Plain object serialization not yet implemented in CodeGen"
            end
          end
        RUBY
      end
    end
  end
end
