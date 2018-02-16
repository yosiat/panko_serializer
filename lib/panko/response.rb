# frozen_string_literal: true
require "oj"

module Panko
  JsonValue = Struct.new(:value) do
    def self.from(value)
      JsonValue.new(value)
    end
  end

  class Response
    def initialize(data)
      @data = data
    end

    def to_json(options = nil)
      writer = Oj::StringWriter.new(mode: :rails)

      writer.push_object

      @data.each do |key, value|
        key = key.to_s

        if value.is_a? Array
          writer.push_array key
          value.each { |v| write_object(writer, v) }
          writer.pop
          next
        end

        write_object writer, value, key

      end

      writer.pop

      writer.to_s
    end

    private

    def write_object(writer, value, key = nil)
     if value.is_a?(Panko::ArraySerializer) ||
        value.is_a?(Panko::Serializer) ||
        value.is_a?(Panko::Response)
       writer.push_json(value.to_json, key)
     elsif value.is_a?(Panko::JsonValue)
       writer.push_json(value.value, key)
     else
       writer.push_value(value, key)
     end
    end
  end
end
