# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates PORO attribute write methods (literal method calls).
      #
      # Hash-object methods (+_write_hash+, +_write_hash_hash+) use
      # +object[key]+ and live as pre-written loops on {GeneratedBase}.
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

        # --- Hash path ---

        def gen_write_plain_hash
          e = Emitter.new
          e << "def self._write_plain_hash(object, result, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_plain_attr_hash(i, attr.name_sym, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end
      end
    end
  end
end
