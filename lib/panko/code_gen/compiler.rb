# frozen_string_literal: true

module SerializersCodeGen
  # Orchestrates one +Compile+ call per +docs/compilation.md § What
  # Compile does internally+: runs semantic validation, asks the
  # +Generator+ for source bytes, materializes them into a fresh
  # anonymous class via +Module#module_eval+ with a synthetic
  # backtrace path, then walks the Descriptor tree depth-first to
  # populate the identity-keyed +CompileCache+ (one entry per unique
  # nested Descriptor in the tree). Returns the root class.
  # +Compile+ is a pure function; repeated calls produce two
  # independent, functionally-identical class trees.
  #
  # The same +Generator+ output drives both materialization paths —
  # +Compiler+ here, +Dump+ in S15. Anything observable in the in-memory
  # form must also be observable in the on-disk form (the
  # +Compile ≡ Dump byte-identical+ contract from
  # +docs/structure.md § Layered architecture+).
  class Compiler
    # Per-mode suffix appended to +Descriptor#name+ to form the inner
    # Generated Class constant — +"JSON"+ for +:json+, +"Hash"+ for
    # +:hash+ — per +docs/generated-class.md+ and the +<Name>_Hash+
    # sketch in +docs/implementation-plan.md § S3+. An explicit table
    # rather than +to_s.upcase+ so the +:hash+ → +"Hash"+ casing matches
    # the docs verbatim.
    OUTPUT_SUFFIXES = {json: "JSON", hash: "Hash"}.freeze

    # @param descriptor [SerializersCodeGen::Descriptor] the input
    # @param output [Symbol] +:json+ or +:hash+
    # @param config [SerializersCodeGen::Config] resolved settings
    # @param validator [Validators::Validator] semantic-validation
    #   orchestrator; defaults to a fresh empty-rule-list instance
    # @param generator [Generator] source-emission entry; defaults to a
    #   fresh instance
    # @param cache [CompileCache] identity-keyed Descriptor → class map
    #   threaded through the post-eval depth-first descent so each
    #   unique nested Descriptor in the tree gets cached exactly once.
    #   Single-level recursion only in S5.1 (parent → distinct child);
    #   full cycle handling lands in S8.
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

    # Validates, emits source for the whole tree, and materializes a
    # fresh anonymous namespace containing one Generated Class per
    # unique Descriptor in the tree. Children are emitted before
    # parents so each parent constructor's reference to its nested
    # +<Inner>_<Suffix>+ class resolves at module_eval time.
    #
    # @return [Class] the freshly-built root Generated Class
    # @raise [SerializersCodeGen::CompileError] when a registered
    #   semantic rule rejects the input
    # @raise [ArgumentError] when +output:+ is not one of
    #   {Generator::OUTPUT_MODES}
    def compile
      @validator.validate(@descriptor, output: @output, config: @config)
      source = @generator.emit(@descriptor, output: @output, config: @config)
      namespace = Class.new
      namespace.module_eval(source, synthetic_path, 1)
      cache_descendants(@descriptor, namespace)
      @cache.get(@descriptor)
    end

    private

    # Returns the synthetic backtrace path stamped into +Method#source_location+
    # per +docs/code-generation.md § Backtrace quality+. The path
    # identifies the Generator-emitted code without colliding with any
    # real file on disk. Shared across every class in one Compile (the
    # whole tree's source is +module_eval+'d in one call).
    #
    # @return [String] e.g. +"(serializers-code-gen: PostSerializer/json)"+
    def synthetic_path
      "(serializers-code-gen: #{@descriptor.name}/#{@output})"
    end

    # Depth-first walk of the Descriptor tree, populating +@cache+ with
    # each unique Descriptor's freshly-materialized Generated Class.
    # +CompileCache#get+ short-circuits the walk when a Descriptor has
    # already been visited — the hook S8 extends with full cycle
    # handling. In S5.1 the recursion is single-level (parent → distinct
    # child) so the short-circuit only matters for shared inner
    # Descriptors referenced from two siblings.
    #
    # @param descriptor [SerializersCodeGen::Descriptor]
    # @param namespace [Class] the anonymous outer that received the
    #   tree's emitted source via +module_eval+
    # @return [void]
    def cache_descendants(descriptor, namespace)
      return if @cache.get(descriptor)
      klass = namespace.const_get(:"#{descriptor.name}_#{OUTPUT_SUFFIXES.fetch(@output)}")
      @cache.set(descriptor, klass)
      descriptor.associations.each do |assoc|
        cache_descendants(assoc.descriptor, namespace)
      end
    end
  end
end
