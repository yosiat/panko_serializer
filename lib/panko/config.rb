# frozen_string_literal: true

module Panko
  # Runtime configuration for Panko's serialization engine. Settings are
  # process-global and read at serialize time — mutate them in an
  # initializer, before serializers start compiling:
  #
  #   Panko.configure do |config|
  #     config.auto_specialization.capacity = 32
  #   end
  #
  # or directly: +Panko::Config.auto_specialization.capacity = 32+.
  class Config
    # Settings for the auto-specialization variant cache — the engine
    # compiles a specialized Generated Class per record class it sees
    # (see +Panko::CodeGen::SerializerCache.variant_pool+).
    class AutoSpecialization
      # @return [Boolean] whether first-sight specialized compiles happen
      #   at all; +false+ routes every record class to the generic path
      attr_reader :enabled

      # @return [Integer] max specialized variants per (serializer class,
      #   output mode); record classes seen past the cap use the generic
      #   path (with a one-time warning per serializer class)
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

    class << self
      # @return [Panko::Config::AutoSpecialization]
      attr_reader :auto_specialization
    end
  end

  # Yields the {Config} class for block-style configuration.
  #
  # @yieldparam config [Class<Panko::Config>]
  # @return [void]
  def self.configure
    yield Config
  end
end
