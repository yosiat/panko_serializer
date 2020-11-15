# frozen_string_literal: true

require "oj"

module Panko
  JsonValue = Struct.new(:value) do
    def self.from(value)
      JsonValue.new(value)
    end

    def to_json
      value
    end
  end

  class ResponseCreator
    def self.value(value)
      Panko::Response.new(value)
    end

    def self.json(value)
      Panko::JsonValue.from(value)
    end

    def self.array_serializer(data, serializer, options = {})
      merged_options = options.merge(each_serializer: serializer)
      Panko::ArraySerializer.new(data, merged_options)
    end

    def self.serializer(data, serializer, options = {})
      json serializer.new(options).serialize_to_json(data)
    end
  end

  class Response
    def initialize(data)
      @data = data
    end

    def to_json(_options = nil)
      writer = Oj::StringWriter.new(mode: :rails)
      write(writer, @data)
      writer.to_s
    end

    def self.create
      Response.new(yield ResponseCreator)
    end

    private

    def write(writer, data, key = nil)
      return write_array(writer, data, key) if data.is_a?(Array)

      return write_object(writer, data, key) if data.is_a?(Hash)

      write_value(writer, data, key)
    end

    def write_array(writer, value, key = nil)
      writer.push_array key
      value.each { |v| write(writer, v) }
      writer.pop
    end

    def write_object(writer, value, key = nil)
      writer.push_object key

      value.each do |entry_key, entry_value|
        write(writer, entry_value, entry_key.to_s)
      end

      writer.pop
    end

    def write_value(writer, value, key = nil)
      if value.is_a?(Panko::ArraySerializer) ||
         value.is_a?(Panko::Serializer) ||
         value.is_a?(Panko::Response) ||
         value.is_a?(Panko::JsonValue)
        writer.push_json(value.to_json, key)
      else
        writer.push_value(value, key)
      end
    end
  end
end
