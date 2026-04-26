# frozen_string_literal: true

module SerializersCodeGen
  module Validators
    # Orchestrator for semantic validation. Holds an ordered list of
    # rule modules and runs them against the (Descriptor, Output Mode,
    # Config) triple at the top of every +Compile+ call, raising on the
    # first violation per +docs/errors.md § Validator orchestrator+.
    #
    # The rule list grows one entry per validator slice — S4.1 plugs in
    # +callable_arity+; S6 will add +source_resolution+; S9 will add
    # +name_uniqueness+. Each rule module exposes a single
    # +.validate(descriptor, output:, config:)+ entry point that raises
    # the appropriate +CompileError+ subclass on violation.
    class Validator
      # Library-default rule list. Iterated in declaration order; the
      # first rule that raises short-circuits the rest. Each rule slice
      # adds its own require in +lib/serializers_code_gen.rb+ + an entry
      # to this constant.
      DEFAULT_RULES = [CallableArity].freeze

      # @param rules [Array<#validate>] override the rule list at
      #   construction time — primarily a test-affordance escape hatch.
      # @return [Validator]
      def initialize(rules: DEFAULT_RULES)
        @rules = rules
      end

      # Runs every registered rule against the input triple. Returns
      # +nil+ on success; raises on the first rule that raises.
      #
      # @param descriptor [SerializersCodeGen::Descriptor] the input
      # @param output [Symbol] resolved Output Mode
      # @param config [SerializersCodeGen::Config] resolved settings
      # @return [void]
      # @raise [SerializersCodeGen::CompileError] on the first rule
      #   violation; the raising rule decides the concrete subclass.
      def validate(descriptor, output:, config:)
        @rules.each { |rule| rule.validate(descriptor, output: output, config: config) }
        nil
      end
    end
  end
end
