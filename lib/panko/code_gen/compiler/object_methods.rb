# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates Hash and PORO attribute write methods.
      module ObjectMethods
        private

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
      end
    end
  end
end
