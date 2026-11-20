# frozen_string_literal: true

require "active_support/inflector"

module Panko
  # Process-global settings, read at serialize time. Set them in an
  # initializer, before serializers compile:
  #
  #   Panko.configure do |config|
  #     config.auto_specialization.capacity = 32
  #   end
  class Config
    # The engine compiles a specialized Generated Class for each named
    # ActiveRecord class a serializer sees, up to +capacity+.
    class AutoSpecialization
      # @return [Boolean] +false+ routes every record class to the generic path
      attr_reader :enabled

      # @return [Integer] max specialized variants per serializer class and output
      #   mode; past it, record classes use the generic path, with one warning
      #   per serializer class
      attr_reader :capacity

      def initialize
        @enabled = true
        @capacity = 16
      end

      def enabled=(value)
        unless value.equal?(true) || value.equal?(false)
          raise ArgumentError,
            "auto_specialization.enabled: must be true or false; got #{value.inspect}:#{value.class}"
        end
        @enabled = value
      end

      def capacity=(value)
        unless value.is_a?(Integer) && value.positive?
          raise ArgumentError,
            "auto_specialization.capacity: must be a positive Integer; got #{value.inspect}:#{value.class}"
        end
        @capacity = value
      end
    end

    KEY_TRANSFORMS = [nil, :camel_lower, :camel, :dash, :underscore].freeze

    @auto_specialization = AutoSpecialization.new
    @writer_pool_max_bytes = 1_048_576
    @key_transform = nil

    class << self
      attr_reader :auto_specialization

      # Largest +serialize_to_json+ output, in bytes, whose writer goes back to
      # the pool. +Oj::StringWriter#reset+ keeps the grown buffer, so a larger
      # writer is dropped instead of holding that memory. Read on every checkin.
      #
      # @return [Integer] default 1_048_576 (1 MB)
      attr_reader :writer_pool_max_bytes

      def writer_pool_max_bytes=(value)
        unless value.is_a?(Integer) && value.positive?
          raise ArgumentError,
            "writer_pool_max_bytes: must be a positive Integer; got #{value.inspect}:#{value.class}"
        end
        @writer_pool_max_bytes = value
      end

      # Output key casing for declared attribute and association names:
      # +:camel_lower+ (+created_at+ to +createdAt+), +:camel+ (+CreatedAt+),
      # +:dash+ (+created-at+), +:underscore+ (+createdAt+ to +created_at+),
      # or +nil+ to keep them as declared. Read when a serializer declares a
      # field, so set it before serializer classes load. +aliases+ and
      # +name:+ keys are kept as written.
      #
      # @return [Symbol, nil] default +nil+
      attr_reader :key_transform

      def key_transform=(value)
        unless KEY_TRANSFORMS.include?(value)
          raise ArgumentError,
            "key_transform: must be :camel_lower, :camel, :dash, :underscore or nil; got #{value.inspect}:#{value.class}"
        end
        @key_transform = value
      end

      # @param key [Symbol] a declared field name
      # @return [Symbol] +key+ in the configured {key_transform} casing
      def transform_key(key)
        case @key_transform
        when :camel_lower then ActiveSupport::Inflector.camelize(key.to_s, false).to_sym
        when :camel then ActiveSupport::Inflector.camelize(key.to_s).to_sym
        when :dash then ActiveSupport::Inflector.dasherize(ActiveSupport::Inflector.underscore(key.to_s)).to_sym
        when :underscore then ActiveSupport::Inflector.underscore(key.to_s).to_sym
        else key
        end
      end
    end
  end

  # Yields the {Config} class for block-style configuration.
  def self.configure
    yield Config
  end
end
