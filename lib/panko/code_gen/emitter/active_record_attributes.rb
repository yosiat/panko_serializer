# frozen_string_literal: true

module Panko
  module CodeGen
    class Emitter
      # AR attribute emit methods for the hot path — indexed cached writes.
      # Both JSON (writer) and Hash (result) variants.
      # All methods include +attr_mask[i]+ guards so a single generated method
      # handles both filtered and unfiltered calls (via {FilterMask::EMPTY}).
      #
      # Cold-path methods (first-pass, fallback) are pre-written loops on
      # {GeneratedBase} and do not need emitters.
      module ActiveRecordAttributes
        # --- Indexed cached hot path (post-warmup, JSON) ---

        def emit_cached_attr(i)
          self << "if attr_mask[#{i}]"
          self << "  v = row[aw.col[#{i}]]"
          self << "  if aw.dir[#{i}]"
          self << "    writer.push_value(v, aw.key[#{i}])"
          self << "  elsif v.nil?"
          self << "    writer.push_value(nil, aw.key[#{i}])"
          self << "  else"
          self << "    aw.wtr[#{i}].write(v, writer, aw.key[#{i}])"
          self << "  end"
          self << "end"
        end

        # --- Indexed cached hot path (post-warmup, Hash) ---

        def emit_cached_attr_hash(i)
          self << "if attr_mask[#{i}]"
          self << "  v = row[aw.col[#{i}]]"
          self << "  if aw.dir[#{i}]"
          self << "    result[aw.key[#{i}]] = v"
          self << "  elsif v.nil?"
          self << "    result[aw.key[#{i}]] = nil"
          self << "  else"
          self << "    _write_cached_value_hash(aw, #{i}, v, result)"
          self << "  end"
          self << "end"
        end
      end
    end
  end
end
