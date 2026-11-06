# frozen_string_literal: true

module Panko::CodeGen
  module Validators
    class Validator
      # Order matters: an arity error is reported before a source or name error.
      DEFAULT_RULES = [CallableArity, SourceResolution, NameUniqueness].freeze

      def initialize(rules: DEFAULT_RULES)
        @rules = rules
      end

      def validate(descriptor, output:, config:)
        @rules.each { |rule| rule.validate(descriptor, output: output, config: config) }
        nil
      end
    end
  end
end
