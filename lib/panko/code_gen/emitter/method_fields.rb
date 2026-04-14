# frozen_string_literal: true

module Panko
  module CodeGen
    class Emitter
      # Emit methods for serializer method field calls.
      module MethodFields
        def emit_method_field(method_name, serialization_key)
          self << "result = ser.#{method_name}"
          self << "writer.push_value(result, #{serialization_key.inspect}) unless result.equal?(Panko::Engine::SKIP)"
        end

        def emit_method_field_filtered(i, method_name, serialization_key)
          self << "if mf_mask.nil? || mf_mask[#{i}]"
          self << "  result = ser.#{method_name}"
          self << "  writer.push_value(result, #{serialization_key.inspect}) unless result.equal?(Panko::Engine::SKIP)"
          self << "end"
        end

        # --- Hash path variants ---

        def emit_method_field_hash(method_name, serialization_key)
          self << "v = ser.#{method_name}"
          self << "result[#{serialization_key.inspect}] = v.as_json unless v.equal?(Panko::Engine::SKIP)"
        end

        def emit_method_field_hash_filtered(i, method_name, serialization_key)
          self << "if mf_mask.nil? || mf_mask[#{i}]"
          self << "  v = ser.#{method_name}"
          self << "  result[#{serialization_key.inspect}] = v.as_json unless v.equal?(Panko::Engine::SKIP)"
          self << "end"
        end
      end
    end
  end
end
