# frozen_string_literal: true

module Panko::CodeGen
  # Orchestrates one +Dump+ call: validates the caller-supplied
  # +path:+, runs the same semantic validator stack as +Compiler+, and
  # writes one +.rb+ file per unique +Generated Class+ in the
  # +Descriptor+ tree. Flat +Descriptors+ (no Associations) produce a
  # single file at the caller-supplied +path:+; nested / Recursive
  # +Descriptors+ fan out to one file per unique +Descriptor+ via
  # {Generators::Fanout},
  # with the outer file at +path:+ and inner files as siblings in the
  # same directory (snake_case +Descriptor+ name + +"_<output>.rb"+).
  #
  # Per-Generated-Class class bytes share {Generator}'s emit
  # machinery with {Compiler}, satisfying the
  # +Compile ≡ Dump byte-identical+ contract at the per-class
  # boundary. The fan-out wrapping (banner, +require_relative+) is
  # the materialization layer's responsibility and lives in
  # {Generators::Fanout}.
  class Dump
    # @param descriptor [Panko::CodeGen::Descriptor] the input
    # @param output [Symbol] +:json+ or +:hash+
    # @param config [Panko::CodeGen::Config] resolved settings
    # @param path [String] the on-disk target file path; required, must
    #   be a non-empty +String+ — anything else fails fast at {#dump}
    #   before any side effect.
    #   For a +Descriptor+ tree with Associations, +path:+ names the
    #   *outer* file; inner sibling files land alongside it under
    #   their snake_case +Descriptor+ basenames.
    # @param validator [Validators::Validator] semantic-validation
    #   orchestrator; defaults to a fresh instance with the library's
    #   default rule list
    # @param generator [Generator] source-emission entry; defaults to a
    #   fresh instance — shared with +Compiler+ so the emit shape stays
    #   single-source. Only consulted by the flat (single-file) path;
    #   the multi-file fan-out routes through {Generators::Fanout},
    #   which reuses {Generators::ClassEmitter#emit_class}
    #   directly to avoid re-walking the tree per file.
    # @return [Dump]
    def initialize(descriptor, output:, config:, path:,
      validator: Validators::Validator.new, generator: Generator.new)
      @descriptor = descriptor
      @output = output
      @config = config
      @path = path
      @validator = validator
      @generator = generator
    end

    # Validates the +path:+ argument, runs the validator stack against
    # the input triple, then writes one or more +.rb+ files. Path
    # validation runs first so an invalid +path:+ surfaces an
    # +ArgumentError+ before any disk side effect — no partial writes,
    # no validator / Generator invocation. The flat path writes a
    # single file at +path:+; the fan-out path writes the outer file
    # at +path:+ and each inner file as a sibling under its snake_case
    # +Descriptor+ basename in the same directory.
    #
    # @return [String] the +path:+ argument the outer file's bytes
    #   were written to (matches +path:+ verbatim — no rewriting)
    # @raise [ArgumentError] when +path:+ is +nil+, an empty String, or
    #   not a String
    # @raise [ArgumentError] when +output:+ is not one of
    #   {Generator::OUTPUT_MODES}
    # @raise [Panko::CodeGen::CompileError] when a registered
    #   semantic rule rejects the input
    def dump
      validate_path!
      @validator.validate(@descriptor, output: @output, config: @config)
      if @descriptor.associations.empty?
        write_flat
      else
        write_fan_out
      end
      @path
    end

    private

    # Pre-flight check on +@path+ — runs before the validator and the
    # Generator so an invalid +@path+ never reaches +File.write+ and
    # never leaves a partial file behind. Required (no default), must
    # be a +String+, must be non-empty.
    #
    # @return [void]
    # @raise [ArgumentError] when +@path+ is not a String, or is an
    #   empty String
    def validate_path!
      unless @path.is_a?(String)
        raise ArgumentError,
          "path: must be a String, got #{@path.class} (#{@path.inspect})"
      end
      raise ArgumentError, "path: must not be empty" if @path.empty?
    end

    # Single-file flat write path — the original S15.2 shape.
    # Reuses {Generator#emit} so flat byte-identity with Compile is
    # mechanically guaranteed (both materializations consume the same
    # +Generator+ output bytes).
    #
    # @return [void]
    def write_flat
      source = @generator.emit(@descriptor, output: @output, config: @config)
      File.write(@path, source)
    end

    # Multi-file fan-out write path — one file per unique +Generated
    # Class+ in the tree. The outer file lands at +@path+ verbatim
    # (caller's choice); each inner file lands as a sibling under
    # +Generators::Fanout.basename_for(descriptor, output)+ in the
    # same directory. Inner-file paths are derived, never accepted —
    # the +require_relative+ directives in the outer file embed
    # those derived basenames, so any caller-overridable inner path
    # would break the wiring.
    #
    # @return [void]
    def write_fan_out
      directory = File.dirname(@path)
      Generators::Fanout.emit_files(@descriptor, output: @output, config: @config).each do |file|
        target = file[:descriptor].equal?(@descriptor) ? @path : File.join(directory, file[:basename])
        File.write(target, file[:source])
      end
    end
  end
end
