# frozen_string_literal: true

module Panko
  module CodeGen
    class Emitter
      # Emit methods for Hash and PORO (plain Ruby object) attribute reads.
      # All methods take literal names baked in at compile time —
      # no +public_send+ or runtime attr lookups.
      module ObjectAttributes
        # --- Hash object (JSON path) ---

        def emit_hash_attr(name, serialization_key)
          self << "writer.push_value(object[#{name.inspect}], #{serialization_key.inspect})"
        end

        def emit_hash_attr_filtered(i, name, serialization_key)
          self << "if attr_mask[#{i}]"
          self << "  writer.push_value(object[#{name.inspect}], #{serialization_key.inspect})"
          self << "end"
        end

        # --- Plain/PORO object (JSON path) ---

        def emit_plain_attr(name_sym, serialization_key)
          self << "writer.push_value(object.#{name_sym}, #{serialization_key.inspect})"
        end

        def emit_plain_attr_filtered(i, name_sym, serialization_key)
          self << "if attr_mask[#{i}]"
          self << "  writer.push_value(object.#{name_sym}, #{serialization_key.inspect})"
          self << "end"
        end

        # --- Hash object (Hash path) ---

        def emit_hash_attr_hash(name, serialization_key)
          self << "result[#{serialization_key.inspect}] = object[#{name.inspect}].as_json"
        end

        def emit_hash_attr_hash_filtered(i, name, serialization_key)
          self << "if attr_mask[#{i}]"
          self << "  result[#{serialization_key.inspect}] = object[#{name.inspect}].as_json"
          self << "end"
        end

        # --- Plain/PORO object (Hash path) ---

        def emit_plain_attr_hash(name_sym, serialization_key)
          self << "result[#{serialization_key.inspect}] = object.#{name_sym}.as_json"
        end

        def emit_plain_attr_hash_filtered(i, name_sym, serialization_key)
          self << "if attr_mask[#{i}]"
          self << "  result[#{serialization_key.inspect}] = object.#{name_sym}.as_json"
          self << "end"
        end
      end
    end
  end
end
