# frozen_string_literal: true

module Panko
  class Configuration
    InitializeError = Class.new(StandardError)

    CAMEL_CASE_LOWER = "camelCase"
    CAMEL_CASE = "CamelCase"
    AVAILABLE_KEY_TYPES = [CAMEL_CASE_LOWER, CAMEL_CASE].freeze

    attr_reader :key_type

    def initialize
      @key_type = nil
    end

    def key_type=(value)
      raise InitializeError, "Invalid key type" unless AVAILABLE_KEY_TYPES.include?(key_type)
      @key_type = value
    end
  end
end
