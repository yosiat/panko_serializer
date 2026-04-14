# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates Hash and PORO attribute write methods.
      # Both JSON (writer) and Hash (result) variants.
      module ObjectMethods
        private

        # --- JSON path ---

        def gen_write_hash
          e = Emitter.new
          e << "def self._write_hash(object, writer)"
          @attrs.each { |attr| e.emit_hash_attr(attr.name, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        def gen_write_hash_filtered
          e = Emitter.new
          e << "def self._write_hash_filtered(object, writer, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_hash_attr_filtered(i, attr.name, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        def gen_write_plain
          e = Emitter.new
          e << "def self._write_plain(object, writer)"
          @attrs.each { |attr| e.emit_plain_attr(attr.name_sym, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        def gen_write_plain_filtered
          e = Emitter.new
          e << "def self._write_plain_filtered(object, writer, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_plain_attr_filtered(i, attr.name_sym, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        # --- Hash path ---

        def gen_write_hash_hash
          e = Emitter.new
          e << "def self._write_hash_hash(object, result)"
          @attrs.each { |attr| e.emit_hash_attr_hash(attr.name, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        def gen_write_hash_hash_filtered
          e = Emitter.new
          e << "def self._write_hash_hash_filtered(object, result, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_hash_attr_hash_filtered(i, attr.name, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        def gen_write_plain_hash
          e = Emitter.new
          e << "def self._write_plain_hash(object, result)"
          @attrs.each { |attr| e.emit_plain_attr_hash(attr.name_sym, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        def gen_write_plain_hash_filtered
          e = Emitter.new
          e << "def self._write_plain_hash_filtered(object, result, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_plain_attr_hash_filtered(i, attr.name_sym, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end
      end
    end
  end
end
