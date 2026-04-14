# frozen_string_literal: true

module Panko
  module CodeGen
    class Emitter
      # Emit methods for serializer method field calls.
      # All methods include mask guards for unified filtered/unfiltered handling.
      module MethodFields
        def emit_method_field(i, method_name, serialization_key)
          self << "if mf_mask.nil? || mf_mask[#{i}]"
          self << "  result = ser.#{method_name}"
          self << "  writer.push_value(result, #{serialization_key.inspect}) unless result.equal?(Panko::Engine::SKIP)"
          self << "end"
        end

        def emit_method_field_hash(i, method_name, serialization_key)
          self << "if mf_mask.nil? || mf_mask[#{i}]"
          self << "  v = ser.#{method_name}"
          self << "  result[#{serialization_key.inspect}] = v.as_json unless v.equal?(Panko::Engine::SKIP)"
          self << "end"
        end
      end
    end
  end
end
