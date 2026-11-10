# frozen_string_literal: true

module Panko::CodeGen
  class Compiler
    # A table, not +to_s.upcase+: the +:hash+ suffix is +Hash+, not +HASH+.
    OUTPUT_SUFFIXES = {json: "JSON", hash: "Hash"}.freeze

    def initialize(descriptor, output:, config:)
      @descriptor = descriptor
      @output = output
      @config = config
      # Identity, not equality: equal but distinct Descriptors compile to separate classes.
      @compiled = {}.compare_by_identity
    end

    def compile
      Validators::Validator.validate(@descriptor, output: @output, config: @config)
      source = Generator.emit(@descriptor, output: @output, config: @config)
      namespace = Class.new
      bind_anonymous_parents(namespace)
      evaluate(namespace, source)
      collect_classes(@descriptor, namespace)
      @compiled.fetch(@descriptor)
    end

    private

    # SyntaxError is a ScriptError, which a bare +rescue+ (Panko.compile_all, the
    # auto-specialization fallback) does not catch.
    def evaluate(namespace, source)
      namespace.module_eval(source, synthetic_path, 1)
    rescue SyntaxError => error
      raise CompileError, "#{@descriptor.name}: generated #{@output} source does not parse: #{error.message}"
    end

    # A Hash, not one constant per class: +const_set+ gives an anonymous class a name,
    # which would change +parent_class.name+ for the next compile.
    def bind_anonymous_parents(namespace)
      anonymous = {}
      Generators::DescriptorWalk.in_emit_order(@descriptor).each do |descriptor|
        parent = descriptor.parent_class
        next if parent.name
        anonymous[descriptor.name] = parent
      end
      namespace.const_set(:ANON_PARENTS, anonymous.freeze) unless anonymous.empty?
    end

    def synthetic_path
      "(#{GENERATOR_NAME}: #{@descriptor.name}/#{@output})"
    end

    # Records the class before descending, so a cycle back to this Descriptor stops here.
    def collect_classes(descriptor, namespace)
      return if @compiled.key?(descriptor)
      @compiled[descriptor] = namespace.const_get(:"#{descriptor.name}_#{OUTPUT_SUFFIXES.fetch(@output)}")
      descriptor.associations.each do |assoc|
        assoc.descriptors.each { |child| collect_classes(child, namespace) }
      end
    end
  end
end
