# frozen_string_literal: true

module Panko::CodeGen
  # Orchestrates one +Compile+ call per +docs/code_gen/compilation.md § What
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
  # +docs/code_gen/structure.md § Layered architecture+).
  class Compiler
    # Per-mode suffix appended to +Descriptor#name+ to form the inner
    # Generated Class constant — +"JSON"+ for +:json+, +"Hash"+ for
    # +:hash+ — per +docs/code_gen/generated-class.md+. An explicit table
    # rather than +to_s.upcase+ so the +:hash+ → +"Hash"+ casing matches
    # the docs verbatim.
    OUTPUT_SUFFIXES = {json: "JSON", hash: "Hash"}.freeze

    # @param descriptor [Panko::CodeGen::Descriptor] the input
    # @param output [Symbol] +:json+ or +:hash+
    # @param config [Panko::CodeGen::Config] resolved settings
    # @param validator [Validators::Validator] semantic-validation
    #   orchestrator; defaults to a fresh empty-rule-list instance
    # @param generator [Generator] source-emission entry; defaults to a
    #   fresh instance
    # @return [Compiler]
    def initialize(descriptor, output:, config:, validator: Validators::Validator.new,
      generator: Generator.new)
      @descriptor = descriptor
      @output = output
      @config = config
      @validator = validator
      @generator = generator
      @cache = CompileCache.new
    end

    # Validates, emits source for the whole tree, and materializes a
    # fresh anonymous namespace containing one Generated Class per
    # unique Descriptor in the tree. Children are emitted before
    # parents so each parent constructor's reference to its nested
    # +<Inner>_<Suffix>+ class resolves at module_eval time.
    #
    # @return [Class] the freshly-built root Generated Class
    # @raise [Panko::CodeGen::CompileError] when a registered
    #   semantic rule rejects the input
    # @raise [ArgumentError] when +output:+ is not one of
    #   {Generator::OUTPUT_MODES}
    def compile
      @validator.validate(@descriptor, output: @output, config: @config)
      source = @generator.emit(@descriptor, output: @output, config: @config)
      namespace = Class.new
      bind_anonymous_parents(namespace)
      namespace.module_eval(source, synthetic_path, 1)
      cache_descendants(@descriptor, namespace)
      @cache.get(@descriptor)
    end

    private

    # Exposes each anonymous +parent_class+ in the tree so the emitted
    # +class <Name>_<Mode> < ANON_PARENTS.fetch("<Name>")+ line resolves at
    # +module_eval+ time. Panko's DSL exposes anonymous serializers
    # (+Class.new(Panko::Serializer)+), which the converter still sets as a
    # +parent_class+; a named parent is referenced by its own constant instead.
    #
    # Deliberately a Hash of +name => Class+ rather than one constant per class:
    # +const_set(name, aClass)+ *names* an anonymous class as a side effect,
    # which would corrupt a subsequent compile that reads +parent_class.name+.
    # A Hash value carries no such naming.
    #
    # @param namespace [Class] the fresh anonymous outer about to receive the
    #   emitted source
    # @return [void]
    def bind_anonymous_parents(namespace)
      anonymous = {}
      Generators::DescriptorWalk.in_emit_order(@descriptor).each do |descriptor|
        parent = descriptor.parent_class
        next if parent.nil? || parent.name
        anonymous[descriptor.name] = parent
      end
      namespace.const_set(:ANON_PARENTS, anonymous.freeze) unless anonymous.empty?
    end

    # Returns the synthetic backtrace path stamped into +Method#source_location+
    # per +docs/code_gen/code-generation.md § Backtrace quality+. The path
    # identifies the Generator-emitted code without colliding with any
    # real file on disk. Shared across every class in one Compile (the
    # whole tree's source is +module_eval+'d in one call).
    #
    # @return [String] e.g. +"(Panko::CodeGen: PostSerializer/json)"+
    def synthetic_path
      "(#{GENERATOR_NAME}: #{@descriptor.name}/#{@output})"
    end

    # Depth-first walk of the Descriptor tree, populating +@cache+ with
    # each unique Descriptor's freshly-materialized Generated Class.
    # Uses +CompileCache#lookup_or_compile+ so the parent's class is
    # registered *before* recursing into its Associations — a
    # self-referential or back-edge +Association+ to a Descriptor
    # that's still being walked finds the in-progress class and
    # short-circuits, breaking what would otherwise be an infinite
    # descent (S8.1 self-recursion; S8.2 mutual recursion uses the
    # same shape at construction time).
    #
    # @param descriptor [Panko::CodeGen::Descriptor]
    # @param namespace [Class] the anonymous outer that received the
    #   tree's emitted source via +module_eval+
    # @return [void]
    def cache_descendants(descriptor, namespace)
      @cache.lookup_or_compile(descriptor) do
        klass = namespace.const_get(:"#{descriptor.name}_#{OUTPUT_SUFFIXES.fetch(@output)}")
        @cache.set(descriptor, klass)
        descriptor.associations.each do |assoc|
          cache_descendants(assoc.descriptor, namespace)
        end
      end
    end
  end
end
