# frozen_string_literal: true

module Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter
  class StringWriter
    def write(value, writer, key)
      case value
      when String
        writer.push_value(value, key)
      when TrueClass
        writer.push_value("t", key)
      when FalseClass
        writer.push_value("f", key)
      else
        writer.push_value(value.to_s, key)
      end

      # we always write.. we have "else" case
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
