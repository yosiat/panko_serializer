# frozen_string_literal: true

module Panko
  class Configuration
    InitializeError = Class.new(StandardError)

    CAMEL_CASE_LOWER = "camelCase"
    CAMEL_CASE = "CamelCase"

    AVAILABLE_KEY_TYPES = [CAMEL_CASE_LOWER, CAMEL_CASE].freeze

    attr_accessor :key_type

    def initialize
      @key_type = nil
    end

    def validate
      validate_key_type
    end

    private

    def validate_key_type
      return unless key_type

      raise InitializeError, "Invalid key type" unless AVAILABLE_KEY_TYPES.include?(key_type)
    end
  end
end
