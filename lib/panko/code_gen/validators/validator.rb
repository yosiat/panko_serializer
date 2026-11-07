# frozen_string_literal: true

module Panko::CodeGen
  module Validators
    module Validator
      # Order matters: an arity error is reported before a source or name error.
      RULES = [CallableArity, SourceResolution, NameUniqueness].freeze

      def self.validate(descriptor, output:, config:)
        RULES.each { |rule| rule.validate(descriptor, output: output, config: config) }
        nil
      end
    end
  end
end
