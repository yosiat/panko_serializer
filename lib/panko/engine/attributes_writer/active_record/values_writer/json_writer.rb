# frozen_string_literal: true

module Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter
  class JsonWriter
    def write(value, writer, key)
      if is_json_value?(value)
        writer.push_json(value, key)
        return true
      end

      false
    end

    # JSON values require validation/parsing and cannot be written
    # with a simple +push_value+ call.
    # @return [Boolean]
    def nil_safe_push?
      false
    end

    private

    SC_PARSE_HANDLER = Object.new.freeze

    def is_json_value?(value)
      return value unless value.is_a?(String)

      return false if value.length == 0

      begin
        result = Oj.sc_parse(SC_PARSE_HANDLER, value)

        return true if result.nil?
        return false if result == false
      rescue Oj::ParseError
        return false
      end

      false
    end
  end
end
