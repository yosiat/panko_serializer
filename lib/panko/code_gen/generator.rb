# frozen_string_literal: true

module Panko::CodeGen
  # Generator entry point — the one place an Output Mode Symbol resolves
  # to its {Generators::Sink} adapter. Domain-aware: drives the shared
  # {Generators::ClassEmitter} over the Descriptor tree and returns the
  # source string. Knows nothing about +module_eval+ or +File.write+ —
  # that materialization happens one layer up in +Compiler+ / +Dump+,
  # and both consume the same bytes (the Compile ≡ Dump byte-identical
  # contract from +docs/code_gen/structure.md § Layered architecture+).
  class Generator
    # The set of accepted +output:+ values.
    OUTPUT_MODES = %i[json hash].freeze

    # The two adapters are stateless; one frozen instance each serves
    # every emit.
    SINKS = {
      json: Generators::JsonSink.new.freeze,
      hash: Generators::HashSink.new.freeze
    }.freeze

    # Resolves an Output Mode to its Sink adapter — the single dispatch
    # home ({Generators::Fanout} consumes it too).
    #
    # @param output [Symbol] +:json+ or +:hash+
    # @return [Panko::CodeGen::Generators::Sink]
    # @raise [ArgumentError] when +output+ is not in {OUTPUT_MODES}
    def self.sink_for(output)
      SINKS.fetch(output) do
        raise ArgumentError, "unknown output mode #{output.inspect}; must be one of #{OUTPUT_MODES.inspect}"
      end
    end

    # Emits source for one (Descriptor, Output Mode, Config) triple.
    #
    # @param descriptor [Panko::CodeGen::Descriptor] the input
    # @param output [Symbol] +:json+ or +:hash+
    # @param config [Panko::CodeGen::Config] resolved settings
    # @return [String] the emitted Ruby source
    # @raise [ArgumentError] when +output+ is not in {OUTPUT_MODES}
    def emit(descriptor, output:, config:)
      Generators::ClassEmitter.new(self.class.sink_for(output)).emit(descriptor, config)
    end
  end
end
