# frozen_string_literal: true

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

    @auto_specialization = AutoSpecialization.new
    @writer_pool_max_bytes = 1_048_576

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
    end
  end

  # Yields the {Config} class for block-style configuration.
  def self.configure
    yield Config
  end
end
