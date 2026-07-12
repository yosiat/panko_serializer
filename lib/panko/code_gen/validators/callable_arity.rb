# frozen_string_literal: true

module Panko::CodeGen
  module Validators
    # Semantic-validation rule: every Callable in a Descriptor tree
    # (+MethodAttribute#body+ and +Association#if+) must declare arity in
    # +{0, 1, 2, 3}+ per +docs/code_gen/descriptor.md § Callable arity+. Variadic
    # arities (+-1+, +-2+, ...) and 4-or-more positional args raise
    # +Panko::CodeGen::ArityError+ before any source emit.
    #
    # First concrete rule plugged into the +Validator+ orchestrator from
    # S2; the module shape (single +.validate(descriptor, output:, config:)+
    # entry, identity-keyed walk) is the template for +source_resolution+
    # (S6) and +name_uniqueness+ (S9).
    module CallableArity
      # Accepted arities for a +Callable+. The +Generator+ emits one
      # specialized call expression per value (+cb.call+, +cb.call(record)+,
      # +cb.call(record, context)+, +cb.call(record, context, scope)+) —
      # anything outside this set has no well-defined emit shape, so the
      # validator rejects it at +Compile+. Arity 3 was added in S17.1
      # (#90) as the foundation for first-class +Scope+ threading; arity 2
      # keeps its existing +(record, context)+ meaning.
      ALLOWED_ARITIES = 0..3

      # Walks +descriptor+ depth-first and raises on the first +Callable+
      # whose arity is outside {ALLOWED_ARITIES}. Uses an identity-keyed
      # visit set so a shared inner Descriptor (or a recursive one — full
      # recursion lands in S8) is walked exactly once.
      #
      # @param descriptor [Panko::CodeGen::Descriptor] root of the walk
      # @param output [Symbol] resolved Output Mode; accepted to satisfy
      #   the orchestrator interface, ignored here (arity is mode-agnostic)
      # @param config [Panko::CodeGen::Config] resolved settings;
      #   accepted to satisfy the orchestrator interface, ignored here
      # @return [void]
      # @raise [Panko::CodeGen::ArityError] on the first Callable
      #   whose arity is not 0, 1, 2, or 3
      def self.validate(descriptor, output:, config:)
        walk(descriptor, {})
        nil
      end

      class << self
        private

        # Recursive depth-first traversal. The +seen+ Hash is keyed by
        # Descriptor identity (+__id__+) — matches the contract from
        # +docs/code_gen/descriptor.md § Recursive Descriptors+ ("Recursion is
        # detected via Ruby object identity").
        #
        # Symbol-body +MethodAttribute+s (S18) are skipped — Symbols have
        # no +#arity+, and the legitimacy check ("Symbol body requires a
        # +parent_class+") lives in +Validators::SymbolBodyDispatch+.
        # Association +#if+ stays Callable-only and is checked as before.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @param seen [Hash{Integer => true}] identity-keyed visit set
        # @return [void]
        def walk(descriptor, seen)
          return if seen[descriptor.__id__]
          seen[descriptor.__id__] = true
          descriptor.method_attributes.each do |ma|
            next if ma.body.is_a?(Symbol)
            check_arity!(descriptor.name, ma.name, "MethodAttribute#body", ma.body.arity)
          end
          descriptor.associations.each do |assoc|
            check_arity!(descriptor.name, assoc.name, "Association#if", assoc.if.arity) if assoc.if
            walk(assoc.descriptor, seen)
          end
        end

        # Raises +ArityError+ with the +docs/code_gen/errors.md § Message convention+
        # format: +"<Descriptor>#<Field>: <CallableLabel> has arity <n>;
        # must be 0, 1, 2, or 3."+.
        #
        # @param descriptor_name [String] +Descriptor#name+
        # @param field_name [Symbol] the offending Field's +name+
        # @param callable_label [String] e.g. +"MethodAttribute#body"+
        # @param arity [Integer] the observed arity
        # @return [void]
        # @raise [Panko::CodeGen::ArityError] when +arity+ is not in
        #   {ALLOWED_ARITIES}
        def check_arity!(descriptor_name, field_name, callable_label, arity)
          return if ALLOWED_ARITIES.include?(arity)
          raise ArityError,
            "#{descriptor_name}##{field_name}: #{callable_label} has arity #{arity}; must be 0, 1, 2, or 3."
        end
      end
    end
  end
end
