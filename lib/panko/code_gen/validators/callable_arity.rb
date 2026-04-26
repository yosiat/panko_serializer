# frozen_string_literal: true

module SerializersCodeGen
  module Validators
    # Semantic-validation rule: every Callable in a Descriptor tree
    # (+MethodAttribute#body+ and +Association#if+) must declare arity in
    # +{0, 1, 2}+ per +docs/descriptor.md § Callable arity+. Variadic
    # arities (+-1+, +-2+, ...) and 3-or-more positional args raise
    # +SerializersCodeGen::ArityError+ before any source emit.
    #
    # First concrete rule plugged into the +Validator+ orchestrator from
    # S2; the module shape (single +.validate(descriptor, output:, config:)+
    # entry, identity-keyed walk) is the template for +source_resolution+
    # (S6) and +name_uniqueness+ (S9).
    module CallableArity
      # Accepted arities for a +Callable+. The +Generator+ emits one
      # specialized call expression per value (+cb.call+, +cb.call(record)+,
      # +cb.call(record, context)+) — anything outside this set has no
      # well-defined emit shape, so the validator rejects it at +Compile+.
      ALLOWED_ARITIES = 0..2

      # Walks +descriptor+ depth-first and raises on the first +Callable+
      # whose arity is outside {ALLOWED_ARITIES}. Uses an identity-keyed
      # visit set so a shared inner Descriptor (or a recursive one — full
      # recursion lands in S8) is walked exactly once.
      #
      # @param descriptor [SerializersCodeGen::Descriptor] root of the walk
      # @param output [Symbol] resolved Output Mode; accepted to satisfy
      #   the orchestrator interface, ignored here (arity is mode-agnostic)
      # @param config [SerializersCodeGen::Config] resolved settings;
      #   accepted to satisfy the orchestrator interface, ignored here
      # @return [void]
      # @raise [SerializersCodeGen::ArityError] on the first Callable
      #   whose arity is not 0, 1, or 2
      def self.validate(descriptor, output:, config:)
        walk(descriptor, {})
        nil
      end

      class << self
        private

        # Recursive depth-first traversal. The +seen+ Hash is keyed by
        # Descriptor identity (+__id__+) — matches the contract from
        # +docs/descriptor.md § Recursive Descriptors+ ("Recursion is
        # detected via Ruby object identity").
        #
        # @param descriptor [SerializersCodeGen::Descriptor]
        # @param seen [Hash{Integer => true}] identity-keyed visit set
        # @return [void]
        def walk(descriptor, seen)
          return if seen[descriptor.__id__]
          seen[descriptor.__id__] = true
          descriptor.method_attributes.each do |ma|
            check_arity!(descriptor.name, ma.name, "MethodAttribute#body", ma.body.arity)
          end
          descriptor.associations.each do |assoc|
            check_arity!(descriptor.name, assoc.name, "Association#if", assoc.if.arity) if assoc.if
            walk(assoc.descriptor, seen)
          end
        end

        # Raises +ArityError+ with the +docs/errors.md § Message convention+
        # format: +"<Descriptor>#<Field>: <CallableLabel> has arity <n>;
        # must be 0, 1, or 2."+.
        #
        # @param descriptor_name [String] +Descriptor#name+
        # @param field_name [Symbol] the offending Field's +name+
        # @param callable_label [String] e.g. +"MethodAttribute#body"+
        # @param arity [Integer] the observed arity
        # @return [void]
        # @raise [SerializersCodeGen::ArityError] when +arity+ is not in
        #   {ALLOWED_ARITIES}
        def check_arity!(descriptor_name, field_name, callable_label, arity)
          return if ALLOWED_ARITIES.include?(arity)
          raise ArityError,
            "#{descriptor_name}##{field_name}: #{callable_label} has arity #{arity}; must be 0, 1, or 2."
        end
      end
    end
  end
end
