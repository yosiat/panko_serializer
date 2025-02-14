# frozen_string_literal: true

module Panko::Impl::AttributesWriter::ActiveRecord::ValuesWriter
  class JsonWriter
    def write(value, writer, key)
      if is_json_value?(value)
        writer.push_json(value, key)
        return true
      end

      false
    end

    private

    def is_json_value?(value)
      return value unless value.is_a?(String)

      return false if value.length == 0

      begin
        result = Oj.sc_parse(Object.new, value)

        return true if result.nil?
        return false if result == false
      rescue Oj::ParseError
        return false
      end

      false
    end
  end
end
