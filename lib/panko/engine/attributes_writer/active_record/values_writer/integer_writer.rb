# frozen_string_literal: true

module Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter
  class IntegerWriter
    def write(value, writer, key)
      if value.is_a?(Integer)
        writer.push_value(value, key)
        return true
      elsif value.is_a?(String) && !value.empty?
        writer.push_value(value.to_i, key)
        return true
      elsif value.is_a?(Float)
        writer.push_value(value.to_i, key)
        return true
      elsif value == true
        writer.push_value(1, key)
        return true
      elsif value == false
        writer.push_value(0, key)
        return true
      end

      # At this point, we handled integer, float, string and booleans
      # any thing other than this (array, hashes, etc), so we should write nil.
      writer.push_value(nil, key)
      true
    end

    # Whether +push_value+ alone is sufficient for this writer's common types,
    # allowing the caller to skip the nil check and writer dispatch entirely.
    # @return [Boolean]
    def nil_safe_push?
      true
    end
  end
end
