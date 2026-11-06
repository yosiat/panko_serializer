# frozen_string_literal: true

module Panko::CodeGen
  class Generator
    OUTPUT_MODES = %i[json hash].freeze

    # Sinks are stateless, so one frozen instance per mode serves every emit.
    SINKS = {
      json: Generators::JsonSink.new.freeze,
      hash: Generators::HashSink.new.freeze
    }.freeze

    def self.sink_for(output)
      SINKS.fetch(output) do
        raise ArgumentError, "unknown output mode #{output.inspect}; must be one of #{OUTPUT_MODES.inspect}"
      end
    end

    def emit(descriptor, output:, config:)
      Generators::ClassEmitter.new(self.class.sink_for(output)).emit(descriptor, config)
    end
  end
end
