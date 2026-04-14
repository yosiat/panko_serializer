# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates AR attribute write methods — indexed cached, first-pass,
      # and dirty/non-indexed fallback paths. All methods accept +attr_mask+
      # for unified filtered/unfiltered handling via {FilterMask::EMPTY}.
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

        def gen_write_indexed_first_pass
          e = Emitter.new
          e << "def self._write_indexed_first_pass(aw, rs, writer, attr_mask)"
          e << "ci = rs.column_indexes"
          e << "row = rs.row"
          e << "attrs = aw.attrs"
          @n.times { |i| e.emit_first_pass_attr(i) }
          e << "end"
          e.to_source
        end

        def gen_write_ar_fallback
          e = Emitter.new
          e << "def self._write_ar_fallback(aw, rs, writer, attr_mask)"
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

        # --- Hash path ---

        def gen_write_indexed_cached_hash
          e = Emitter.new
          e << "def self._write_indexed_cached_hash(row, result, attr_mask)"
          e << "aw = @_ar_writer"
          @n.times { |i| e.emit_cached_attr_hash(i) }
          e << "end"
          e.to_source
        end

        def gen_write_indexed_first_pass_hash
          e = Emitter.new
          e << "def self._write_indexed_first_pass_hash(aw, rs, result, attr_mask)"
          e << "ci = rs.column_indexes"
          e << "row = rs.row"
          e << "attrs = aw.attrs"
          @n.times { |i| e.emit_first_pass_attr_hash(i) }
          e << "end"
          e.to_source
        end

        def gen_write_ar_fallback_hash
          e = Emitter.new
          e << "def self._write_ar_fallback_hash(aw, rs, result, attr_mask)"
          e << "attrs = aw.attrs"
          e << "if rs.is_indexed_row"
          e << "  ci = rs.column_indexes"
          e << "  row = rs.row"
          e << "  ah = rs.attributes_hash"
          @n.times { |i| e.emit_indexed_with_hash_attr_hash(i) }
          e << "else"
          @n.times { |i| e.emit_non_indexed_attr_hash(i) }
          e << "end"
          e << "end"
          e.to_source
        end
      end
    end
  end
end
