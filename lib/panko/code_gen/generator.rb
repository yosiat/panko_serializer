# frozen_string_literal: true

module Panko::CodeGen
  # Generator entry point. Dispatches on +output:+ to the matching per-mode
  # emitter (+JsonMode+ here, +HashMode+ in S3) and returns the source
  # string. Domain-aware: walks the Descriptor tree and decides what to
  # emit. Knows nothing about +module_eval+ or +File.write+ — that
  # materialization happens one layer up in +Compiler+ / +Dump+.
  #
  # The same +#emit+ output drives both materialization paths, satisfying
  # the +Compile ≡ Dump byte-identical+ contract from
  # +docs/code_gen/structure.md § Layered architecture+.
  class Generator
    # The set of accepted +output:+ values. Anything outside this set
    # raises +ArgumentError+ — the dispatch shape is locked from S2.1
    # so S3's +HashMode+ plugs in by extending this list (and the +case+
    # branch below) without restructuring.
    OUTPUT_MODES = %i[json hash].freeze

    # Emits source for one (Descriptor, Output Mode, Config) triple.
    #
    # @param descriptor [Panko::CodeGen::Descriptor] the input
    # @param output [Symbol] +:json+ or +:hash+
    # @param config [Panko::CodeGen::Config] resolved settings
    # @return [String] the emitted Ruby source
    # @raise [ArgumentError] when +output+ is not in {OUTPUT_MODES}
    def emit(descriptor, output:, config:)
      case output
      when :json
        Generators::JsonMode.new.emit(descriptor, config)
      when :hash
        Generators::HashMode.new.emit(descriptor, config)
      else
        raise ArgumentError, "unknown output mode #{output.inspect}; must be one of #{OUTPUT_MODES.inspect}"
      end
    end
  end
end
