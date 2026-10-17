# frozen_string_literal: true

require "oj"
require_relative "code_gen/writers_pool"

module Panko
  JsonValue = Struct.new(:value) do
    def self.from(value)
      JsonValue.new(value)
    end

    def to_json
      value
    end
  end

  # A serializer and the object it serializes, written straight into the Response writer.
  SerializerValue = Struct.new(:serializer, :object) do
    def to_json
      serializer.serialize_to_json(object)
    end

    def write_json(writer, key = nil)
      serializer.write_json(object, writer, key)
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
      Panko::SerializerValue.new(serializer.new(options), data)
    end
  end

  class Response
    # Picked on first use, like the generated classes' pools, so an app that loads
    # ActiveSupport after Panko still shares one writer stack with them.
    def self.writers
      @writers ||= defined?(ActiveSupport::IsolatedExecutionState) ?
        Panko::CodeGen::WritersPool::IsolatedExecutionState.new :
        Panko::CodeGen::WritersPool::ThreadLocal.new
    end

    def initialize(data)
      @data = data
    end

    def to_json(_options = nil)
      writers = Response.writers
      writer = writers.checkout
      result = nil
      begin
        write(writer, @data)
        result = writer.to_s
      ensure
        writers.checkin(writer, result)
      end
    end

    # Writes this Response into +writer+ as the value of +key+, or as the next element when
    # +key+ is nil.
    def write_json(writer, key = nil)
      write(writer, @data, key)
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
      case value
      when Panko::ArraySerializer, Panko::Response, Panko::SerializerValue
        value.write_json(writer, key)
      when Panko::Serializer, Panko::JsonValue
        writer.push_json(value.to_json, key)
      else
        writer.push_value(value, key)
      end
    end
  end
end
