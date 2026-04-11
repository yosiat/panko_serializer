# frozen_string_literal: true

module Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter
  class FloatWriter
    def write(value, writer, key)
      if value.is_a?(Float)
        writer.push_value(value, key)
        true
      elsif value.is_a?(String)
        writer.push_value(value.to_f, key)
        true
      else
        false
      end
    end

    # Whether +push_value+ alone is sufficient for this writer's common types,
    # allowing the caller to skip the nil check and writer dispatch entirely.
    # @return [Boolean]
    def nil_safe_push?
      true
    end
  end
end
