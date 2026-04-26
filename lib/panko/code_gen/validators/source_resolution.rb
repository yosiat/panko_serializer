# frozen_string_literal: true

module SerializersCodeGen
  module Validators
    # Semantic-validation rule: every +Attribute+ on a +Descriptor+ with
    # +models:+ set must resolve to either a column or an instance method
    # on every AR class in +models+ (3-step rule per
    # +docs/compilation.md § Specialized path+). Unresolved Sources raise
    # +UnknownSourceError+ before any source emit, naming the +Descriptor+,
    # +Field+, and observed Source per +docs/errors.md § Message convention+.
    #
    # Second concrete rule plugged into the +Validator+ orchestrator
    # (registered after +CallableArity+ in +Validator::DEFAULT_RULES+).
    # Mirrors +CallableArity+'s shape — single +.validate(descriptor,
    # output:, config:)+ entry, identity-keyed walk so a shared inner
    # Descriptor is visited exactly once.
    #
    # Scope notes:
    # - +models: nil+ (Generic path) — no validation; missing methods
    #   surface at runtime as Ruby's own +NoMethodError+ per
    #   +docs/errors.md+.
    # - Non-AR class in +models:+ (e.g. a +Struct+ or plain +Class.new+) —
    #   skipped. The Specialized path falls back to method dispatch per
    #   +docs/compilation.md § Non-AR class in `models`+.
    # - Multi-class +models:+ (STI / mixed sets) — S6.1 iterates per-class
    #   independently; the strict intersection rule lands in S7
    #   (+docs/compilation.md § STI and mixed class sets+).
    module SourceResolution
      # Walks +descriptor+ depth-first and raises on the first unresolvable
      # Attribute Source against a +models:+ class. Uses an identity-keyed
      # visit set so a shared inner Descriptor (or a recursive one — full
      # recursion lands in S8) is walked exactly once.
      #
      # @param descriptor [SerializersCodeGen::Descriptor] root of the walk
      # @param output [Symbol] resolved Output Mode; accepted to satisfy
      #   the orchestrator interface, ignored here (Source resolution is
      #   mode-agnostic)
      # @param config [SerializersCodeGen::Config] resolved settings;
      #   accepted to satisfy the orchestrator interface, ignored here
      # @return [void]
      # @raise [SerializersCodeGen::UnknownSourceError] on the first
      #   Attribute whose +source+ is neither a column nor an instance
      #   method on its declared AR Model
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
        # established by +CallableArity+.
        #
        # @param descriptor [SerializersCodeGen::Descriptor]
        # @param seen [Hash{Integer => true}] identity-keyed visit set
        # @return [void]
        def walk(descriptor, seen)
          return if seen[descriptor.__id__]
          seen[descriptor.__id__] = true
          classify_attributes!(descriptor) if descriptor.models
          descriptor.associations.each { |assoc| walk(assoc.descriptor, seen) }
        end

        # Iterates every AR class in +descriptor.models+ and classifies
        # every +Attribute+ on +descriptor+ via +AccessClassifier+. Calls
        # +DefineAttributeMethods.ensure!+ once per AR class so AR's lazy
        # column readers are populated before step (2) of the 3-step
        # rule runs.
        #
        # @param descriptor [SerializersCodeGen::Descriptor] a Descriptor
        #   with +models:+ set (caller already gated)
        # @return [void]
        # @raise [SerializersCodeGen::UnknownSourceError] re-raised with
        #   +Descriptor+ / +Field+ context per +docs/errors.md § Message
        #   convention+
        def classify_attributes!(descriptor)
          descriptor.models.each do |model|
            next unless ar_class?(model)
            ActiveRecord::DefineAttributeMethods.ensure!(model)
            descriptor.attributes.each do |attr|
              classify_or_raise!(model, attr, descriptor.name)
            end
          end
        end

        # Calls +AccessClassifier.classify+ and re-raises any
        # +UnknownSourceError+ with the full +docs/errors.md § Message
        # convention+ format. The classifier itself is +(klass, source)+
        # only and knows nothing about Descriptors / Fields; this wrapper
        # bridges that gap.
        #
        # @param klass [Class] AR class being introspected
        # @param attribute [SerializersCodeGen::Attribute] the Field
        #   whose +source+ is being classified
        # @param descriptor_name [String] +Descriptor#name+ for the
        #   message prefix
        # @return [void]
        # @raise [SerializersCodeGen::UnknownSourceError] when the
        #   classifier rejects +attribute.source+
        def classify_or_raise!(klass, attribute, descriptor_name)
          ActiveRecord::AccessClassifier.classify(klass, attribute.source)
          nil
        rescue UnknownSourceError
          raise UnknownSourceError,
            "#{descriptor_name}##{attribute.name}: Attribute#source :#{attribute.source} " \
            "is not a column or instance method on #{klass.name}."
        end

        # Duck-typed AR test: +columns_hash+ is the canonical AR class
        # method the classifier introspects, and +attribute_methods_generated?+
        # is the gate +DefineAttributeMethods.ensure!+ short-circuits on.
        # Non-AR classes in +models:+ (e.g. +Struct+, plain +Class.new+)
        # fail this test and are skipped — the Specialized path emits
        # method dispatch for them per +docs/compilation.md § Non-AR
        # class in `models`+.
        #
        # @param klass [Class]
        # @return [Boolean]
        def ar_class?(klass)
          klass.respond_to?(:columns_hash) && klass.respond_to?(:attribute_methods_generated?)
        end
      end
    end
  end
end
