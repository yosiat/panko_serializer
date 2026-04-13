# frozen_string_literal: true

module Panko
  module CodeGen
    class Emitter
      # Emit methods for Hash and PORO (plain Ruby object) attribute reads.
      module ObjectAttributes
        # --- Hash object ---

        def emit_hash_attr(i)
          self << "writer.push_value(object[attrs[#{i}].name], attrs[#{i}].name_for_serialization)"
        end

        def emit_hash_attr_filtered(i)
          self << "if attr_mask[#{i}]"
          self << "  writer.push_value(object[attrs[#{i}].name], attrs[#{i}].name_for_serialization)"
          self << "end"
        end

        # --- Plain (PORO) object ---

        def emit_plain_attr(i)
          self << "writer.push_value(object.public_send(attrs[#{i}].name_sym), attrs[#{i}].name_for_serialization)"
        end

        def emit_plain_attr_filtered(i)
          self << "if attr_mask[#{i}]"
          self << "  writer.push_value(object.public_send(attrs[#{i}].name_sym), attrs[#{i}].name_for_serialization)"
          self << "end"
        end
      end
    end
  end
end
