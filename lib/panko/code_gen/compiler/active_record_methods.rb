# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates the AR hot-path and fallback write methods:
      #
      # - +_write_indexed_cached+ (+ hash) — fully unrolled hot path used after
      #   the first indexed call.
      # - +_write_ar_fallback+ (+ hash) — unrolled per-class. The non-indexed
      #   +else+ branch is unrolled so YJIT can inline each per-attribute
      #   +rs.read_attribute+ + +ValuesWriter.write+ pair; the indexed branch
      #   stays as a loop (cold path — only used when a record has a dirty
      #   attributes hash).
      #
      # The remaining cold path (+_write_indexed_first_pass+) is still a
      # pre-written loop on {GeneratedBase}; unrolling it would only help on
      # the very first call per record class and would bloat the generated
      # source.
      module ActiveRecordMethods
        private

        # --- JSON path ---

        def gen_write_indexed_cached
          e = Emitter.new
          e << "def self._write_indexed_cached(row, writer, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_cached_attr(i, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        # Generates +_write_ar_fallback+ per-class. The method body mirrors
        # the pre-written version on {GeneratedBase} for the indexed branch
        # (cold — each_with_index loop stays), and unrolls the non-indexed
        # else branch into one +if attr_mask[i]+ block per attribute.
        #
        # TODO(perf): for serializers with a very large attribute count (say
        # 32+), the unrolled method may exceed YJIT's inlining budget and
        # become slower than the loop. If you hit a regression on a wide
        # serializer, gate on +@n >= SOME_THRESHOLD+ here and emit a loop
        # instead. No benchmark data yet — leaving unrolled for all sizes.
        def gen_write_ar_fallback
          e = Emitter.new
          e << "def self._write_ar_fallback(aw, rs, writer, attr_mask)"
          e << "  attrs = aw.attrs"
          e << "  if rs.is_indexed_row"
          e << "    ci = rs.column_indexes"
          e << "    row = rs.row"
          e << "    ah = rs.attributes_hash"
          e << "    attrs.each_with_index do |attr, i|"
          e << "      next unless attr_mask[i]"
          e << ""
          e << "      v = nil"
          e << "      am = ah[attr.name]"
          e << "      if am"
          e << "        v = am.instance_variable_get(:@value_before_type_cast)"
          e << "        attr.type ||= am.instance_variable_get(:@type)"
          e << "      end"
          e << "      if v.nil?"
          e << "        ci_val = ci[attr.name]"
          e << "        v = row[ci_val] if ci_val"
          e << "      end"
          e << "      _resolve_type(attr, rs) if attr.type.nil? && v"
          e << "      _write_value(attr, v, writer)"
          e << "    end"
          e << "  else"
          @attrs.each_with_index { |_attr, i| e.emit_fallback_attr(i) }
          e << "  end"
          e << "end"
          e.to_source
        end

        # --- Hash path ---

        def gen_write_indexed_cached_hash
          e = Emitter.new
          e << "def self._write_indexed_cached_hash(row, result, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_cached_attr_hash(i, attr.name_for_serialization) }
          e << "end"
          e.to_source
        end

        # Hash-path variant of +gen_write_ar_fallback+.
        def gen_write_ar_fallback_hash
          e = Emitter.new
          e << "def self._write_ar_fallback_hash(aw, rs, result, attr_mask)"
          e << "  attrs = aw.attrs"
          e << "  if rs.is_indexed_row"
          e << "    ci = rs.column_indexes"
          e << "    row = rs.row"
          e << "    ah = rs.attributes_hash"
          e << "    attrs.each_with_index do |attr, i|"
          e << "      next unless attr_mask[i]"
          e << ""
          e << "      v = nil"
          e << "      am = ah[attr.name]"
          e << "      if am"
          e << "        v = am.instance_variable_get(:@value_before_type_cast)"
          e << "        attr.type ||= am.instance_variable_get(:@type)"
          e << "      end"
          e << "      if v.nil?"
          e << "        ci_val = ci[attr.name]"
          e << "        v = row[ci_val] if ci_val"
          e << "      end"
          e << "      _resolve_type(attr, rs) if attr.type.nil? && v"
          e << "      _write_value_hash(attr, v, result)"
          e << "    end"
          e << "  else"
          @attrs.each_with_index { |_attr, i| e.emit_fallback_attr_hash(i) }
          e << "  end"
          e << "end"
          e.to_source
        end
      end
    end
  end
end
