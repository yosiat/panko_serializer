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

        # AR attribute write methods
        define_on(klass, gen_write_indexed_cached, "_write_indexed_cached")
        define_on(klass, gen_write_indexed_cached_filtered, "_write_indexed_cached_filtered")
        define_on(klass, gen_write_indexed_first_pass, "_write_indexed_first_pass")
        define_on(klass, gen_write_indexed_first_pass_filtered, "_write_indexed_first_pass_filtered")
        define_on(klass, gen_write_ar_fallback, "_write_ar_fallback")
        define_on(klass, gen_write_ar_fallback_filtered, "_write_ar_fallback_filtered")

        # Non-AR attribute write methods
        define_on(klass, gen_write_hash, "_write_hash")
        define_on(klass, gen_write_hash_filtered, "_write_hash_filtered")
        define_on(klass, gen_write_plain, "_write_plain")
        define_on(klass, gen_write_plain_filtered, "_write_plain_filtered")

        # Method fields
        if @has_method_fields
          ser = @serializer_type.new(_skip_init: true)
          ser.serialization_context = @descriptor.serializer.serialization_context
          klass._serializer = ser
          define_on(klass, gen_write_method_fields, "_write_method_fields")
          define_on(klass, gen_write_method_fields_filtered, "_write_method_fields_filtered")
        end

        # Associations
        if @has_has_one
          klass._has_one_assocs = @has_one_assocs
          klass._ho_static_masks = compute_static_masks(@has_one_assocs)
          define_on(klass, gen_write_has_one, "_write_has_one")
          define_on(klass, gen_write_has_one_filtered, "_write_has_one_filtered")
        end

        if @has_has_many
          klass._has_many_assocs = @has_many_assocs
          klass._hm_static_masks = compute_static_masks(@has_many_assocs)
          define_on(klass, gen_write_has_many, "_write_has_many")
          define_on(klass, gen_write_has_many_filtered, "_write_has_many_filtered")
        end

        # Top-level dispatch
        define_on(klass, gen_write_one, "_write_one")
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

      # --- Indexed cached hot path ---

      def gen_write_indexed_cached
        e = Emitter.new
        e << "def self._write_indexed_cached(row, writer)"
        e << "aw = @_ar_writer"
        @n.times { |i| e.emit_cached_attr(i) }
        e << "end"
        e.to_source
      end

      def gen_write_indexed_cached_filtered
        e = Emitter.new
        e << "def self._write_indexed_cached_filtered(row, writer, attr_mask)"
        e << "aw = @_ar_writer"
        @n.times { |i| e.emit_cached_attr_filtered(i) }
        e << "end"
        e.to_source
      end

      # --- Indexed first pass ---

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

      # --- AR fallback ---

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

      # --- Hash / Plain ---

      def gen_write_hash
        e = Emitter.new
        e << "def self._write_hash(object, writer)"
        e << "attrs = @_attrs"
        @n.times { |i| e.emit_hash_attr(i) }
        e << "end"
        e.to_source
      end

      def gen_write_hash_filtered
        e = Emitter.new
        e << "def self._write_hash_filtered(object, writer, attr_mask)"
        e << "attrs = @_attrs"
        @n.times { |i| e.emit_hash_attr_filtered(i) }
        e << "end"
        e.to_source
      end

      def gen_write_plain
        e = Emitter.new
        e << "def self._write_plain(object, writer)"
        e << "attrs = @_attrs"
        @n.times { |i| e.emit_plain_attr(i) }
        e << "end"
        e.to_source
      end

      def gen_write_plain_filtered
        e = Emitter.new
        e << "def self._write_plain_filtered(object, writer, attr_mask)"
        e << "attrs = @_attrs"
        @n.times { |i| e.emit_plain_attr_filtered(i) }
        e << "end"
        e.to_source
      end

      # --- Method fields ---

      def gen_write_method_fields
        e = Emitter.new
        e << "def self._write_method_fields(object, writer, context)"
        e << "ser = @_serializer"
        e << "ser.serialization_context = context"
        e << "ser.instance_variable_set(:@object, object)"
        @method_fields.each { |mf| e.emit_method_field(mf.name_sym, mf.name_for_serialization) }
        e << "end"
        e.to_source
      end

      def gen_write_method_fields_filtered
        e = Emitter.new
        e << "def self._write_method_fields_filtered(object, writer, mf_mask, context)"
        e << "ser = @_serializer"
        e << "ser.serialization_context = context"
        e << "ser.instance_variable_set(:@object, object)"
        @method_fields.each_with_index { |mf, i| e.emit_method_field_filtered(i, mf.name_sym, mf.name_for_serialization) }
        e << "end"
        e.to_source
      end

      # --- Associations ---

      def gen_write_has_one
        e = Emitter.new
        e << "def self._write_has_one(object, writer, context)"
        @has_one_assocs.each_with_index { |a, i| e.emit_has_one(i, a.name_sym, a.name_str) }
        e << "end"
        e.to_source
      end

      def gen_write_has_one_filtered
        e = Emitter.new
        e << "def self._write_has_one_filtered(object, writer, filter_mask, context)"
        e << "ho_mask = filter_mask.has_one"
        e << "ho_masks = filter_mask.has_one_masks"
        @has_one_assocs.each_with_index { |a, i| e.emit_has_one_filtered(i, a.name_sym, a.name_str) }
        e << "end"
        e.to_source
      end

      def gen_write_has_many
        e = Emitter.new
        e << "def self._write_has_many(object, writer, context)"
        @has_many_assocs.each_with_index { |a, i| e.emit_has_many(i, a.name_sym, a.name_str) }
        e << "end"
        e.to_source
      end

      def gen_write_has_many_filtered
        e = Emitter.new
        e << "def self._write_has_many_filtered(object, writer, filter_mask, context)"
        e << "hm_mask = filter_mask.has_many"
        e << "hm_masks = filter_mask.has_many_masks"
        @has_many_assocs.each_with_index { |a, i| e.emit_has_many_filtered(i, a.name_sym, a.name_str) }
        e << "end"
        e.to_source
      end

      # --- Top-level dispatch ---

      # Generates +_serialize_many+ — type dispatch once per batch,
      # then tight per-type loops with inlined extras.
      def gen_serialize_many
        has_extras = @has_method_fields || @has_has_one || @has_has_many

        e = Emitter.new
        e << "def self._serialize_many(objects, writer, key = nil, filter_mask: nil, context: nil)"
        e << "  writer.push_array(key)"
        e << "  if objects.empty?"
        e << "    writer.pop"
        e << "    return"
        e << "  end"
        e << ""
        e << "  first = objects.is_a?(Array) ? objects[0] : objects.first"

        e << "  if first.is_a?(ActiveRecord::Base)"
        emit_typed_loop(e, "@_ar_writer.write(obj, writer, filter_mask)", "@_ar_writer.write(obj, writer, nil)", has_extras, ar_path: true)

        e << "  elsif first.is_a?(Hash)"
        emit_typed_loop(e, "_write_hash_filtered(obj, writer, filter_mask.attrs)", "_write_hash(obj, writer)", has_extras)

        e << "  else"
        emit_typed_loop(e, "_write_plain_filtered(obj, writer, filter_mask.attrs)", "_write_plain(obj, writer)", has_extras)

        e << "  end"
        e << "  writer.pop"
        e << "end"
        e.to_source
      end

      # Emits one type-specific loop body for +_serialize_many+.
      # When +has_extras+ is true, splits on filter_mask to call
      # the filtered or unfiltered extras per object.
      # +ar_path+ indicates the AR path where +@_ar_writer.write+
      # handles nil filter_mask internally (no split needed for lean case).
      #
      # @param e [Emitter] the emitter to append to
      # @param filtered_write [String] attribute write call for the filtered path
      # @param unfiltered_write [String] attribute write call for the unfiltered path
      # @param has_extras [Boolean] whether method fields or associations exist
      # @param ar_path [Boolean] true for the ActiveRecord path
      def emit_typed_loop(e, filtered_write, unfiltered_write, has_extras, ar_path: false)
        if has_extras || !ar_path
          # Need filter_mask split: extras need it, and Hash/PORO need it
          # because filtered_write calls filter_mask.attrs
          e << "    if filter_mask"
          emit_loop_body(e, filtered_write, filtered: true)
          e << "    else"
          emit_loop_body(e, unfiltered_write, filtered: false)
        else
          # AR lean path: ar_writer handles nil filter_mask internally
          e << "    objects.each do |obj|"
          e << "      writer.push_object"
          e << "      #{filtered_write}"
          e << "      writer.pop"
        end
        e << "    end"
      end

      # Emits a single objects.each loop body with attribute write + extras.
      def emit_loop_body(e, write_call, filtered:)
        e << "      objects.each do |obj|"
        e << "        writer.push_object"
        e << "        #{write_call}"
        if filtered
          e << "        _write_method_fields_filtered(obj, writer, filter_mask.method_fields, context)" if @has_method_fields
          e << "        _write_has_one_filtered(obj, writer, filter_mask, context)" if @has_has_one
          e << "        _write_has_many_filtered(obj, writer, filter_mask, context)" if @has_has_many
        else
          e << "        _write_method_fields(obj, writer, context)" if @has_method_fields
          e << "        _write_has_one(obj, writer, context)" if @has_has_one
          e << "        _write_has_many(obj, writer, context)" if @has_has_many
        end
        e << "        writer.pop"
        e << "      end"
      end

      # Generates +_write_one+ — object-type dispatch + extras.
      # Only includes filter/method/association dispatch when needed.
      def gen_write_one
        has_extras = @has_method_fields || @has_has_one || @has_has_many

        extras = ""
        if has_extras
          extras = "\n    if filter_mask"
          extras += "\n      _write_method_fields_filtered(object, writer, filter_mask.method_fields, context)" if @has_method_fields
          extras += "\n      _write_has_one_filtered(object, writer, filter_mask, context)" if @has_has_one
          extras += "\n      _write_has_many_filtered(object, writer, filter_mask, context)" if @has_has_many
          extras += "\n    else"
          extras += "\n      _write_method_fields(object, writer, context)" if @has_method_fields
          extras += "\n      _write_has_one(object, writer, context)" if @has_has_one
          extras += "\n      _write_has_many(object, writer, context)" if @has_has_many
          extras += "\n    end"
        end

        <<~RUBY
          def self._write_one(object, writer, filter_mask, context)
            if object.is_a?(ActiveRecord::Base)
              @_ar_writer.write(object, writer, filter_mask)
            elsif object.is_a?(Hash)
              if filter_mask
                _write_hash_filtered(object, writer, filter_mask.attrs)
              else
                _write_hash(object, writer)
              end
            else
              if filter_mask
                _write_plain_filtered(object, writer, filter_mask.attrs)
              else
                _write_plain(object, writer)
              end
            end#{extras}
          end
        RUBY
      end
    end
  end
end
