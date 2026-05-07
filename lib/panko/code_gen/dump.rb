# frozen_string_literal: true

module SerializersCodeGen
  # Orchestrates one +Dump+ call per +docs/dumping.md § Dump to file+:
  # validates the caller-supplied +path:+, runs the same semantic
  # validator stack as +Compiler+, asks the +Generator+ for source
  # bytes, and writes them to disk via +File.write+. The +Generator+
  # output is the same instance shape +Compiler+ feeds to
  # +module_eval+, so the on-disk bytes are byte-identical to the
  # in-memory Compile per the +Compile ≡ Dump byte-identical+ contract
  # from +docs/structure.md § Layered architecture+.
  #
  # S15.2 ships the flat (single-file, no nested fan-out) materialization
  # path. Multi-file fan-out (one file per +Generated Class+ +
  # +require_relative+ topology + Recursive Descriptor handling) lands in
  # S15.5; synthetic-path substitution (Compile retains the synthetic
  # +(serializers-code-gen: <Name>/<output>)+ path; Dump replaces it with
  # the real disk path) lands in S15.3. This class is the single
  # entry point both slices will extend.
  class Dump
    # @param descriptor [SerializersCodeGen::Descriptor] the input
    # @param output [Symbol] +:json+ or +:hash+
    # @param config [SerializersCodeGen::Config] resolved settings
    # @param path [String] the on-disk target file path; required, must
    #   be a non-empty +String+ — anything else fails fast at {#dump}
    #   per +docs/dumping.md § Dumping API+ before any side effect
    # @param validator [Validators::Validator] semantic-validation
    #   orchestrator; defaults to a fresh instance with the library's
    #   default rule list
    # @param generator [Generator] source-emission entry; defaults to a
    #   fresh instance — shared with +Compiler+ so the emit shape stays
    #   single-source
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
    # the input triple, asks the Generator for source bytes, and writes
    # them to +path:+. Path validation runs first so an invalid +path:+
    # surfaces an +ArgumentError+ before any disk side effect — no
    # partial writes, no validator / Generator invocation.
    #
    # @return [String] the +path:+ argument the bytes were written to
    # @raise [ArgumentError] when +path:+ is +nil+, an empty String, or
    #   not a String
    # @raise [ArgumentError] when +output:+ is not one of
    #   {Generator::OUTPUT_MODES}
    # @raise [SerializersCodeGen::CompileError] when a registered
    #   semantic rule rejects the input
    def dump
      validate_path!
      @validator.validate(@descriptor, output: @output, config: @config)
      source = @generator.emit(@descriptor, output: @output, config: @config)
      File.write(@path, source)
      @path
    end

    private

    # Pre-flight check on +@path+ — runs before the validator and the
    # Generator so an invalid +path:+ never reaches +File.write+ and
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
  end
end
