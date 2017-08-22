# frozen_string_literal: true
require "oj"

module Panko
  class Response
    def initialize(data)
      @data = data
    end

    def to_json(options = nil)
      writer = Oj::StringWriter.new(mode: :rails)

      writer.push_object

      @data.each do |key, value|
        if value.is_a?(Panko::ArraySerializer) || value.is_a?(Panko::Serializer)
          writer.push_json(value.to_json, key.to_s)
        else
          writer.push_value(value, key.to_s)
        end
      end

      writer.pop

      writer.to_s
    end
  end
end
