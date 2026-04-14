# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates the AR hot-path write methods — unrolled per-attribute
      # writes for the indexed cached path (post-warmup).
      #
      # Cold-path methods (+_write_indexed_first_pass+, +_write_ar_fallback+)
      # live as pre-written loops on {GeneratedBase}.
      module ActiveRecordMethods
        private

        # --- JSON path ---

        def gen_write_indexed_cached
          e = Emitter.new
          e << "def self._write_indexed_cached(row, writer, attr_mask)"
          e << "aw = @_ar_writer"
          @n.times { |i| e.emit_cached_attr(i) }
          e << "end"
          e.to_source
        end

        # --- Hash path ---

        def gen_write_indexed_cached_hash
          e = Emitter.new
          e << "def self._write_indexed_cached_hash(row, result, attr_mask)"
          e << "aw = @_ar_writer"
          @n.times { |i| e.emit_cached_attr_hash(i) }
          e << "end"
          e.to_source
        end
      end
    end
  end
end
