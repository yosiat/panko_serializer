# frozen_string_literal: true

module Panko
  module CodeGen
    class Emitter
      # AR attribute emit methods for the hot path — indexed cached writes.
      # Both JSON (writer) and Hash (result) variants.
      # All methods include +attr_mask[i]+ guards so a single generated method
      # handles both filtered and unfiltered calls (via {FilterMask::EMPTY}).
      #
      # Generated code uses per-attribute class ivars (+@_col_0+, +@_dir_0+,
      # +@_wtr_0+) populated by {ActiveRecordAttributesWriter#build_caches!},
      # and literal serialization keys baked in at compile time.
      #
      # Cold-path methods (first-pass, fallback) are pre-written loops on
      # {GeneratedBase} and do not need emitters.
      module ActiveRecordAttributes
        # --- Indexed cached hot path (post-warmup, JSON) ---

        # @param i [Integer] attribute index
        # @param serialization_key [String] the JSON key (baked in as literal)
        def emit_cached_attr(i, serialization_key)
          key = serialization_key.inspect
          self << "if attr_mask[#{i}]"
          # +@_col_#{i}+ is nil when the underlying column was omitted from the
          # query (e.g. +select(:a_subset)+); treat a missing column as a nil
          # value instead of indexing +row+ with nil and raising TypeError.
          self << "  v = (c = @_col_#{i}) ? row[c] : nil"
          self << "  if @_dir_#{i}"
          self << "    writer.push_value(v, #{key})"
          self << "  elsif v.nil?"
          self << "    writer.push_value(nil, #{key})"
          self << "  else"
          self << "    @_wtr_#{i}.write(v, writer, #{key})"
          self << "  end"
          self << "end"
        end

        # --- Indexed cached hot path (post-warmup, Hash) ---

        # @param i [Integer] attribute index
        # @param serialization_key [String] the Hash key (baked in as literal)
        def emit_cached_attr_hash(i, serialization_key)
          key = serialization_key.inspect
          self << "if attr_mask[#{i}]"
          # See +emit_cached_attr+: +@_col_#{i}+ is nil when the column was
          # omitted from the query; guard against +row[nil]+.
          self << "  v = (c = @_col_#{i}) ? row[c] : nil"
          self << "  if @_dir_#{i}"
          self << "    result[#{key}] = v"
          self << "  elsif v.nil?"
          self << "    result[#{key}] = nil"
          self << "  else"
          self << "    _write_cached_value_hash(@_wtr_#{i}, @_attrs[#{i}], #{key}, v, result)"
          self << "  end"
          self << "end"
        end
      end
    end
  end
end
