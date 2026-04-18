# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates per-serializer attribute write methods for non-AR objects:
      # +_write_plain+ for POROs (literal method calls) and +_write_hash+
      # for Hash inputs (literal key lookups). Both unroll the attribute
      # loop so there is no +each_with_index+ in the hot path.
      module ObjectMethods
        private

        # --- JSON path ---

        def gen_write_plain
          e = Emitter.new
          e << "def self._write_plain(object, writer, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_plain_attr(i, attr.name_sym, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        def gen_write_hash
          e = Emitter.new
          e << "def self._write_hash(object, writer, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_hash_attr(i, attr.name, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        # --- Hash path ---

        def gen_write_plain_hash
          e = Emitter.new
          e << "def self._write_plain_hash(object, result, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_plain_attr_hash(i, attr.name_sym, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        def gen_write_hash_hash
          e = Emitter.new
          e << "def self._write_hash_hash(object, result, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_hash_attr_hash(i, attr.name, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end
      end
    end
  end
end
