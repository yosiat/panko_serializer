# frozen_string_literal: true

module Panko::CodeGen
  module Validators
    # Semantic-validation rule: every +Attribute+ on a +Descriptor+ with
    # +model:+ set must resolve to either a column or an instance method
    # on the AR Model (3-step rule). Unresolved Sources raise
    # +UnknownSourceError+ before any source emit, naming the +Descriptor+,
    # +Field+, and observed Source.
    #
    # Second concrete rule plugged into the +Validator+ orchestrator
    # (registered after +CallableArity+ in +Validator::DEFAULT_RULES+).
    # Mirrors +CallableArity+'s shape — single +.validate(descriptor,
    # output:, config:)+ entry, identity-keyed walk so a shared inner
    # Descriptor is visited exactly once.
    #
    # Scope notes:
    # - +model: nil+ (Generic path) — no validation; missing methods
    #   surface at runtime as Ruby's own +NoMethodError+.
    # - Non-AR class in +model:+ (e.g. a +Struct+ or plain +Class.new+) —
    #   skipped. The Specialized path falls back to method dispatch.
    module SourceResolution
      # Walks +descriptor+ depth-first and raises on the first unresolvable
      # Attribute Source against the +model:+ class. Uses an identity-keyed
      # visit set so a shared inner Descriptor (or a recursive one — full
      # recursion lands in S8) is walked exactly once.
      #
      # @param descriptor [Panko::CodeGen::Descriptor] root of the walk
      # @param output [Symbol] resolved Output Mode; accepted to satisfy
      #   the orchestrator interface, ignored here (Source resolution is
      #   mode-agnostic)
      # @param config [Panko::CodeGen::Config] resolved settings;
      #   accepted to satisfy the orchestrator interface, ignored here
      # @return [void]
      # @raise [Panko::CodeGen::UnknownSourceError] on the first
      #   Attribute whose +source+ is neither a column nor an instance
      #   method on its declared AR Model
      def self.validate(descriptor, output:, config:)
        walk(descriptor, {})
        nil
      end

      class << self
        private

        # Recursive depth-first traversal. The +seen+ Hash is keyed by
        # Descriptor identity (+__id__+) — matches the contract
        # ("Recursion is detected via Ruby object identity") and the
        # convention established by +CallableArity+.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @param seen [Hash{Integer => true}] identity-keyed visit set
        # @return [void]
        def walk(descriptor, seen)
          return if seen[descriptor.__id__]
          seen[descriptor.__id__] = true
          classify_attributes!(descriptor) if descriptor.model
          descriptor.associations.each { |assoc| walk(assoc.descriptor, seen) }
        end

        # Calls +DefineAttributeMethods.ensure!+ on the AR Model so AR's
        # lazy column readers are populated, then classifies every
        # +Attribute+ on +descriptor+ via +AccessClassifier.classify+.
        #
        # When +descriptor.model+ is not AR-like (e.g. a +Struct+ or a
        # plain +Class.new+), classification is skipped — the Specialized
        # path falls back to method dispatch.
        #
        # @param descriptor [Panko::CodeGen::Descriptor] a Descriptor
        #   with +model:+ set (caller already gated)
        # @return [void]
        # @raise [Panko::CodeGen::UnknownSourceError] re-raised with
        #   +Descriptor+ / +Field+ context per the Message convention
        def classify_attributes!(descriptor)
          model = descriptor.model
          return unless ar_class?(model)
          ActiveRecord::DefineAttributeMethods.ensure!(model)
          descriptor.attributes.each do |attribute|
            classify_or_raise!(model, attribute, descriptor.name)
          end
        end

        # Calls +AccessClassifier.classify+ and re-raises any
        # +UnknownSourceError+ with the full Message convention
        # format. The classifier itself is +(klass, source)+
        # only and knows nothing about Descriptors / Fields; this wrapper
        # bridges that gap.
        #
        # @param model [Class] the AR Model from +descriptor.model+
        # @param attribute [Panko::CodeGen::Attribute] the Field
        #   whose +source+ is being classified
        # @param descriptor_name [String] +Descriptor#name+ for the
        #   message prefix
        # @return [void]
        # @raise [Panko::CodeGen::UnknownSourceError] when the
        #   classifier rejects +attribute.source+
        def classify_or_raise!(model, attribute, descriptor_name)
          ActiveRecord::AccessClassifier.classify(model, attribute.source)
          nil
        rescue UnknownSourceError
          raise UnknownSourceError,
            "#{descriptor_name}##{attribute.name}: Attribute#source :#{attribute.source} " \
            "is not a column or instance method on #{model.name}."
        end

        # Duck-typed AR test: +columns_hash+ is the canonical AR class
        # method the classifier introspects, and +attribute_methods_generated?+
        # is the gate +DefineAttributeMethods.ensure!+ short-circuits on.
        # Non-AR classes in +model:+ (e.g. +Struct+, plain +Class.new+)
        # fail this test and are skipped — the Specialized path emits
        # method dispatch for them.
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
