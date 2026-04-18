# frozen_string_literal: true

module Panko
  module CodeGen
    class Emitter
      # Emit methods for PORO (plain Ruby object) and Hash attribute reads.
      # All methods take literal names baked in at compile time and include
      # +attr_mask[i]+ guards for unified filtered/unfiltered handling.
      module ObjectAttributes
        # --- Plain/PORO object (JSON path) ---

        def emit_plain_attr(i, name_sym, serialization_key)
          self << "if attr_mask[#{i}]"
          self << "  writer.push_value(object.#{name_sym}, #{serialization_key.inspect})"
          self << "end"
        end

        # --- Plain/PORO object (Hash path) ---

        def emit_plain_attr_hash(i, name_sym, serialization_key)
          self << "if attr_mask[#{i}]"
          self << "  result[#{serialization_key.inspect}] = object.#{name_sym}.as_json"
          self << "end"
        end

        # --- Hash object (JSON path) ---
        # Baked lookups: +object["name"]+ with the literal attribute name
        # inlined per attribute, no loop over +@_attrs+.

        def emit_hash_attr(i, name_str, serialization_key)
          self << "if attr_mask[#{i}]"
          self << "  writer.push_value(object[#{name_str.inspect}], #{serialization_key.inspect})"
          self << "end"
        end

        # --- Hash object (Hash path) ---

        def emit_hash_attr_hash(i, name_str, serialization_key)
          self << "if attr_mask[#{i}]"
          self << "  result[#{serialization_key.inspect}] = object[#{name_str.inspect}].as_json"
          self << "end"
        end
      end
    end
  end
end
