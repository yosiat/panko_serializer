# frozen_string_literal: true

module SerializersCodeGen
  # Orchestrates one +Compile+ call per +docs/compilation.md § What
  # Compile does internally+: runs semantic validation, asks the
  # +Generator+ for source bytes, materializes them into a fresh
  # anonymous class via +Module#module_eval+ with a synthetic
  # backtrace path. Returns the class. +Compile+ is a pure function;
  # repeated calls produce two independent, functionally-identical
  # classes.
  #
  # The same +Generator+ output drives both materialization paths —
  # +Compiler+ here, +Dump+ in S15. Anything observable in the in-memory
  # form must also be observable in the on-disk form (the
  # +Compile ≡ Dump byte-identical+ contract from
  # +docs/structure.md § Layered architecture+).
  class Compiler
    # @param descriptor [SerializersCodeGen::Descriptor] the input
    # @param output [Symbol] +:json+ or +:hash+
    # @param config [SerializersCodeGen::Config] resolved settings
    # @param validator [Validators::Validator] semantic-validation
    #   orchestrator; defaults to a fresh empty-rule-list instance
    # @param generator [Generator] source-emission entry; defaults to a
    #   fresh instance
    # @param cache [CompileCache] identity-keyed Descriptor → class map
    #   threaded through nested-Association compile in later slices;
    #   single-entry case here
    # @return [Compiler]
    def initialize(descriptor, output:, config:, validator: Validators::Validator.new,
      generator: Generator.new, cache: CompileCache.new)
      @descriptor = descriptor
      @output = output
      @config = config
      @validator = validator
      @generator = generator
      @cache = cache
    end

    # Validates, emits source, and materializes a fresh class.
    #
    # @return [Class] the freshly-built Generated Class
    # @raise [SerializersCodeGen::CompileError] when a registered
    #   semantic rule rejects the input
    # @raise [ArgumentError] when +output:+ is not one of
    #   {Generator::OUTPUT_MODES}
    def compile
      @validator.validate(@descriptor, output: @output, config: @config)
      source = @generator.emit(@descriptor, output: @output, config: @config)
      generated_class = Class.new
      generated_class.module_eval(source, synthetic_path, 1)
      generated_class.const_get(:"#{@descriptor.name}_#{output_suffix}").tap do |klass|
        @cache.set(@descriptor, klass)
      end
    end

    private

    # Returns the synthetic backtrace path stamped into +Method#source_location+
    # per +docs/code-generation.md § Backtrace quality+. The path
    # identifies the Generator-emitted code without colliding with any
    # real file on disk.
    #
    # @return [String] e.g. +"(serializers-code-gen: PostSerializer/json)"+
    def synthetic_path
      "(serializers-code-gen: #{@descriptor.name}/#{@output})"
    end

    # Returns the per-mode suffix appended to +Descriptor#name+ to form
    # the inner Generated Class constant — +"JSON"+ for +:json+,
    # +"HASH"+ for +:hash+ (S3).
    #
    # @return [String]
    def output_suffix
      @output.to_s.upcase
    end
  end
end
