# frozen_string_literal: true

module Panko::CodeGen
  class Compiler
    # A table, not +to_s.upcase+: the +:hash+ suffix is +Hash+, not +HASH+.
    OUTPUT_SUFFIXES = {json: "JSON", hash: "Hash"}.freeze

    def initialize(descriptor, output:, config:, validator: Validators::Validator.new,
      generator: Generator.new)
      @descriptor = descriptor
      @output = output
      @config = config
      @validator = validator
      @generator = generator
      @cache = CompileCache.new
    end

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

    def cache_descendants(descriptor, namespace)
      @cache.lookup_or_compile(descriptor) do
        klass = namespace.const_get(:"#{descriptor.name}_#{OUTPUT_SUFFIXES.fetch(@output)}")
        @cache.set(descriptor, klass)
        descriptor.associations.each do |assoc|
          assoc.descriptors.each { |child| cache_descendants(child, namespace) }
        end
      end
    end
  end
end
