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
      # - +@_attr_#{i}+, +@_attr_#{i}_key+ — stamped eagerly by
      #   {ActiveRecordAttributesWriter#initialize}. Used by
      #   +emit_fallback_attr+ so the unrolled non-indexed fallback can read
      #   the {Panko::Attribute} and its JSON key by ivar instead of via
      #   +aw.attrs[i]+ / +attribute.name_for_serialization+.
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
        # This is the E6 form: when +cached_writer+ is already populated we
        # call the type-specific writer directly, bypassing the
        # +ValuesWriter.write+ wrapper (which does a thread-local lookup and
        # a +name_for_serialization+ resolution on every call). The cold path
        # (first call per class, +cached_writer+ still nil) still goes through
        # +ValuesWriter.write+ so the writer and type get materialized and
        # cached for subsequent calls.
        #
        # Reads +@_attr_#{i}+ at call time so that +handle_class_change+'s
        # rewrite of +attr.name+ (for AR column aliases) is respected
        # without having to rebuild the generated method. The JSON key is
        # stamped as +@_attr_#{i}_key+ at class build time — see
        # {ActiveRecordAttributesWriter#stamp_attr_ivars!} and the comment
        # there for why caching +name_for_serialization+ is safe.
        #
        # @param i [Integer] attribute index
        def emit_fallback_attr(i)
          self << "if attr_mask[#{i}]"
          self << "  v = rs.read_attribute(@_attr_#{i})"
          # We still use +ValuesWriter+ — just not the dispatch wrapper.
          # After warmup, +attribute.cached_writer+ holds a type-specific
          # writer (+StringWriter+, +IntegerWriter+, ...) that was
          # materialized inside +ValuesWriter::Writer#write+. We call it
          # directly. The +else+ branch below is the cold path for the first
          # call, where +cached_writer+ is still nil and we delegate to
          # +ValuesWriter.write+ to resolve and cache the writer.
          self << "  cw = @_attr_#{i}.cached_writer"
          self << "  if cw"
          self << "    if v.nil?"
          self << "      writer.push_value(nil, @_attr_#{i}_key)"
          self << "    else"
          # +cw.write+ mirrors +Writer#write+'s per-type fast path: it
          # returns falsy if the cached writer cannot serialize +v+ as-is,
          # and we fall back to +type.deserialize(v)+. This matches the
          # +unless cached.write(...)+ branch in +ValuesWriter::Writer#write+.
          self << "      cw.write(v, writer, @_attr_#{i}_key) || writer.push_value(@_attr_#{i}.type.deserialize(v), @_attr_#{i}_key)"
          self << "    end"
          self << "  else"
          self << "    Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, @_attr_#{i}, v)"
          self << "  end"
          self << "end"
        end

        # Hash-path variant of +emit_fallback_attr+. Mirrors the E6 shape
        # but targets a {Panko::CodeGen::ValueCapture} for the hot path so
        # the captured value can be stored in +result+.
        #
        # @param i [Integer] attribute index
        def emit_fallback_attr_hash(i)
          self << "if attr_mask[#{i}]"
          self << "  v = rs.read_attribute(@_attr_#{i})"
          # See +emit_fallback_attr+ for the rationale. The hash variant
          # routes the cached writer's output through a shared
          # {ValueCapture} so we can materialize the coerced Ruby value into
          # the +result+ hash (the cached writer API only writes through an
          # Oj-like writer).
          self << "  cw = @_attr_#{i}.cached_writer"
          self << "  if cw"
          self << "    if v.nil?"
          self << "      result[@_attr_#{i}_key] = nil"
          self << "    else"
          self << "      _write_cached_value_hash(cw, @_attr_#{i}, @_attr_#{i}_key, v, result)"
          self << "    end"
          self << "  else"
          self << "    _write_value_hash(@_attr_#{i}, v, result)"
          self << "  end"
          self << "end"
        end
      end
    end
  end
end
