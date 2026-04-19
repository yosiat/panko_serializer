# frozen_string_literal: true

module Panko
  module CodeGen
    class Emitter
      # AR attribute emit methods for the hot path — indexed cached writes —
      # and for the non-indexed +_write_ar_fallback+ +else+ branch.
      # Both JSON (writer) and Hash (result) variants.
      # All methods include +attr_mask[i]+ guards so a single generated method
      # handles both filtered and unfiltered calls (via {FilterMask::EMPTY}).
      #
      # Generated code uses per-attribute class ivars:
      # - +@_col_#{i}+, +@_wtr_#{i}+, +@_dir_#{i}+ — populated lazily by
      #   {ActiveRecordAttributesWriter#build_caches!} on the first indexed
      #   call. Used by +emit_cached_attr+.
      # - +@_attr_#{i}+ — stamped eagerly by
      #   {ActiveRecordAttributesWriter#initialize}. Used by
      #   +emit_fallback_attr+ so the unrolled non-indexed fallback can read
      #   the {Panko::Attribute} by ivar instead of +aw.attrs[i]+.
      #
      # Serialization keys are baked in as string literals at compile time.
      # The indexed branch of +_write_ar_fallback+ and +_write_indexed_first_pass+
      # remain pre-written loops on {GeneratedBase} / per-class generated
      # loops — they are cold paths and do not need emitters.
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

        # --- Non-indexed fallback (unpersisted / Rails 7.x + dirty records) ---

        # Emits the unrolled per-attribute write for the +else+ branch of
        # +_write_ar_fallback+ on the JSON path. Replaces the
        # +each_with_index+ loop previously used on {GeneratedBase} so YJIT
        # can inline the read-and-dispatch for each attribute.
        #
        # This keeps the existing +ValuesWriter.write+ dispatch semantics
        # (first-call type resolution + +cached_writer+ caching) — the only
        # change is eliminating the loop frame. Direct +cached_writer+
        # dispatch is an E6 concern and lives in a separate commit.
        #
        # Reads +@_attr_#{i}+ at call time so that +handle_class_change+'s
        # rewrite of +attr.name+ (for AR column aliases) is respected
        # without having to rebuild the generated method.
        #
        # @param i [Integer] attribute index
        def emit_fallback_attr(i)
          self << "if attr_mask[#{i}]"
          self << "  v = rs.read_attribute(@_attr_#{i})"
          self << "  Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, @_attr_#{i}, v)"
          self << "end"
        end

        # Hash-path variant of +emit_fallback_attr+.
        #
        # @param i [Integer] attribute index
        def emit_fallback_attr_hash(i)
          self << "if attr_mask[#{i}]"
          self << "  v = rs.read_attribute(@_attr_#{i})"
          self << "  _write_value_hash(@_attr_#{i}, v, result)"
          self << "end"
        end
      end
    end
  end
end
