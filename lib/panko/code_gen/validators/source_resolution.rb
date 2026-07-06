# frozen_string_literal: true

module Panko::CodeGen
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
    # - Multi-class +models:+ (STI / mixed sets, S7.1) —
    #   +AccessClassifier.classify+ accepts the full AR-class subset and
    #   applies the strict intersection rule per +docs/compilation.md §
    #   STI and mixed class sets+ in one shot. Non-AR classes in the set
    #   are filtered out; the validator never asks the classifier about
    #   classes that don't quack like AR.
    module SourceResolution
      # Walks +descriptor+ depth-first and raises on the first unresolvable
      # Attribute Source against a +models:+ class. Uses an identity-keyed
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
        # Descriptor identity (+__id__+) — matches the contract from
        # +docs/descriptor.md § Recursive Descriptors+ ("Recursion is
        # detected via Ruby object identity") and the convention
        # established by +CallableArity+.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @param seen [Hash{Integer => true}] identity-keyed visit set
        # @return [void]
        def walk(descriptor, seen)
          return if seen[descriptor.__id__]
          seen[descriptor.__id__] = true
          classify_attributes!(descriptor) if descriptor.models
          descriptor.associations.each { |assoc| walk(assoc.descriptor, seen) }
        end

        # Filters +descriptor.models+ down to the AR-class subset, calls
        # +DefineAttributeMethods.ensure!+ once per AR class so AR's lazy
        # column readers are populated, then classifies every
        # +Attribute+ on +descriptor+ against the full AR subset via
        # +AccessClassifier.classify+. The intersection rule (column-in-
        # all / method-in-all / else-raise) is applied once per
        # Attribute by the classifier — the validator no longer iterates
        # per-class.
        #
        # When the AR subset is empty (e.g. +models: [Struct.new(...)]+
        # or every class is a plain +Class.new+), classification is
        # skipped — the Specialized path falls back to method dispatch
        # for non-AR classes per +docs/compilation.md § Non-AR class in
        # `models`+.
        #
        # @param descriptor [Panko::CodeGen::Descriptor] a Descriptor
        #   with +models:+ set (caller already gated)
        # @return [void]
        # @raise [Panko::CodeGen::UnknownSourceError] re-raised with
        #   +Descriptor+ / +Field+ context per +docs/errors.md § Message
        #   convention+
        def classify_attributes!(descriptor)
          ar_classes = descriptor.models.select { |model| ar_class?(model) }
          return if ar_classes.empty?
          ar_classes.each { |klass| ActiveRecord::DefineAttributeMethods.ensure!(klass) }
          descriptor.attributes.each do |attribute|
            classify_or_raise!(ar_classes, attribute, descriptor.name)
          end
        end

        # Calls +AccessClassifier.classify+ on the full AR-class subset
        # and re-raises any +UnknownSourceError+ with the full
        # +docs/errors.md § Message convention+ format. The classifier
        # itself is +(klasses, source)+ only and knows nothing about
        # Descriptors / Fields; this wrapper bridges that gap and
        # carries the (already-named-on-the-classifier-message) missing
        # class names through to the wrapped message.
        #
        # @param klasses [Array<Class>] AR-class subset of
        #   +descriptor.models+
        # @param attribute [Panko::CodeGen::Attribute] the Field
        #   whose +source+ is being classified
        # @param descriptor_name [String] +Descriptor#name+ for the
        #   message prefix
        # @return [void]
        # @raise [Panko::CodeGen::UnknownSourceError] when the
        #   classifier rejects +attribute.source+
        def classify_or_raise!(klasses, attribute, descriptor_name)
          ActiveRecord::AccessClassifier.classify(klasses, attribute.source)
          nil
        rescue UnknownSourceError => err
          raise UnknownSourceError,
            "#{descriptor_name}##{attribute.name}: Attribute#source :#{attribute.source} " \
            "is not a column or instance method on #{missing_class_names(err)}."
        end

        # Extracts the comma-separated class-name list from the
        # classifier's raise message. The classifier formats its message
        # as +"<Names>: source :<source> is not a column or instance
        # method."+; everything before the first +": "+ is the list of
        # missing class names. Pulled out so the wrapped message can
        # name every offending class — preserving the single-class
        # message verbatim ("on Post") and naturally extending to
        # multi-class ("on Truck, Motorcycle").
        #
        # @param error [Panko::CodeGen::UnknownSourceError] the
        #   classifier's raise
        # @return [String] e.g. +"Post"+ or +"Truck, Motorcycle"+
        def missing_class_names(error)
          error.message.split(": ", 2).first
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
