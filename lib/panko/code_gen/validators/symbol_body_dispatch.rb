# frozen_string_literal: true

module Panko::CodeGen
  module Validators
    # Semantic-validation rule: a +MethodAttribute+ whose +body+ is a
    # +Symbol+ may only appear in a +Descriptor+ whose +parent_class+ is
    # non-nil. Symbol-body Method Attributes dispatch via direct method
    # dispatch on +self+ per +docs/merging-into-panko.md § Generated Class
    # subclasses the user's Panko serializer+ — the Generated Class must
    # subclass a user-supplied class for the method name to resolve.
    #
    # The legitimacy check cannot live in structural validation because
    # +MethodAttribute.new+ has no view of the owning +Descriptor+'s
    # +parent_class+; the structural rule (widened in S18.1) accepts
    # Symbol unconditionally and defers the chicken-and-egg to this
    # +Compile+-time walk.
    #
    # Fourth concrete rule plugged into the +Validator+ orchestrator
    # (registered after +NameUniqueness+ in +Validator::DEFAULT_RULES+).
    # Mirrors +CallableArity+ / +SourceResolution+ / +NameUniqueness+ —
    # single +.validate(descriptor, output:, config:)+ entry, identity-
    # keyed walk so a shared inner Descriptor (or a self-referential one)
    # is visited exactly once.
    module SymbolBodyDispatch
      # Walks +descriptor+ depth-first and raises +SymbolBodyError+ on
      # the first +MethodAttribute+ with a +Symbol+ body whose owning
      # Descriptor has +parent_class: nil+. Uses an identity-keyed visit
      # set so a shared inner Descriptor (or a self-referential one) is
      # walked exactly once.
      #
      # @param descriptor [Panko::CodeGen::Descriptor] root of the walk
      # @param output [Symbol] resolved Output Mode; accepted to satisfy
      #   the orchestrator interface, ignored here (Symbol-body
      #   legitimacy is mode-agnostic)
      # @param config [Panko::CodeGen::Config] resolved settings;
      #   accepted to satisfy the orchestrator interface, ignored here
      # @return [void]
      # @raise [Panko::CodeGen::SymbolBodyError] on the first Symbol-
      #   body MethodAttribute under a +parent_class: nil+ Descriptor
      def self.validate(descriptor, output:, config:)
        walk(descriptor, {})
        nil
      end

      class << self
        private

        # Recursive depth-first traversal. The +seen+ Hash is keyed by
        # Descriptor identity (+__id__+) — matches the contract from
        # +docs/descriptor.md § Recursive Descriptors+ ("Recursion is
        # detected via Ruby object identity") and the convention
        # established by +CallableArity+ / +SourceResolution+ /
        # +NameUniqueness+.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @param seen [Hash{Integer => true}] identity-keyed visit set
        # @return [void]
        def walk(descriptor, seen)
          return if seen[descriptor.__id__]
          seen[descriptor.__id__] = true
          check_method_attributes!(descriptor)
          descriptor.associations.each { |assoc| walk(assoc.descriptor, seen) }
        end

        # Scans +descriptor.method_attributes+ for Symbol-body entries
        # and raises +SymbolBodyError+ on the first one when the
        # Descriptor's +parent_class+ is +nil+. Callable bodies are
        # ignored (handled by +CallableArity+); a non-nil +parent_class+
        # is the legitimate Symbol-body shape from S18 and short-circuits
        # the scan entirely.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @return [void]
        # @raise [Panko::CodeGen::SymbolBodyError] per +docs/errors.md
        #   § Message convention+
        def check_method_attributes!(descriptor)
          return unless descriptor.parent_class.nil?
          descriptor.method_attributes.each do |ma|
            next unless ma.body.is_a?(Symbol)
            raise SymbolBodyError,
              "#{descriptor.name}##{ma.name}: MethodAttribute#body is a Symbol but " \
              "Descriptor#parent_class is nil; Symbol-body requires a parent class to dispatch against."
          end
        end
      end
    end
  end
end
