# frozen_string_literal: true

module Panko::CodeGen
  module Validators
    # Semantic-validation rule: every +Field+ on a +Descriptor+ must have a
    # +name+ that is unique among the Fields at the same level. Duplicates
    # across +attributes+, +method_attributes+, and +associations+ all raise
    # +NameCollisionError+ before any source emit, since each Field
    # contributes exactly one output key — a shared +name+ produces
    # ambiguous output (overwrite in Hash mode, duplicate key in JSON
    # mode).
    #
    # Third concrete rule plugged into the +Validator+ orchestrator
    # (registered after +SourceResolution+ in +Validator::DEFAULT_RULES+).
    # Mirrors the +CallableArity+ / +SourceResolution+ shape — single
    # +.validate(descriptor, output:, config:)+ entry, identity-keyed walk
    # so a shared inner Descriptor (or a recursive one) is visited
    # exactly once.
    #
    # Scope: the rule is *per-level*. Same-name across different levels
    # (e.g. +Post.id+ and +Post.author.id+) is fine and does not raise —
    # each recursive call builds its own +seen_names+ map.
    module NameUniqueness
      # Walks +descriptor+ depth-first and raises on the first duplicate
      # Field +name+ at any level. Uses an identity-keyed visit set so a
      # shared inner Descriptor (or a self-referential one) is walked
      # exactly once.
      #
      # @param descriptor [Panko::CodeGen::Descriptor] root of the walk
      # @param output [Symbol] resolved Output Mode; accepted to satisfy
      #   the orchestrator interface, ignored here (name uniqueness is
      #   structural and mode-agnostic)
      # @param config [Panko::CodeGen::Config] resolved settings;
      #   accepted to satisfy the orchestrator interface, ignored here
      # @return [void]
      # @raise [Panko::CodeGen::NameCollisionError] on the first pair
      #   of Fields at the same level that share a +name+
      def self.validate(descriptor, output:, config:)
        walk(descriptor, {})
        nil
      end

      class << self
        private

        # Recursive depth-first traversal. The +seen_descriptors+ Hash is
        # keyed by Descriptor identity (+__id__+) — matches the contract
        # from +docs/code_gen/descriptor.md § Recursive Descriptors+ ("Recursion
        # is detected via Ruby object identity") and the convention
        # established by +CallableArity+ / +SourceResolution+.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @param seen_descriptors [Hash{Integer => true}] identity-keyed
        #   visit set across the whole walk
        # @return [void]
        def walk(descriptor, seen_descriptors)
          return if seen_descriptors[descriptor.__id__]
          seen_descriptors[descriptor.__id__] = true
          check_level!(descriptor)
          descriptor.associations.each { |assoc| walk(assoc.descriptor, seen_descriptors) }
        end

        # Scans the three Field-kind arrays on +descriptor+ in declaration
        # order (Attributes → MethodAttributes → Associations) and raises
        # on the first +name+ collision. Each level builds its own
        # +seen_names+ map — same-name across different levels never
        # interacts.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @return [void]
        # @raise [Panko::CodeGen::NameCollisionError] on the first
        #   pair of Fields sharing a +name+ at this level
        def check_level!(descriptor)
          seen_names = {}
          fields_with_kinds(descriptor).each do |field, kind|
            previous_kind = seen_names[field.name]
            if previous_kind
              raise NameCollisionError,
                "#{descriptor.name}##{field.name}: #{previous_kind} and #{kind} share name; " \
                "every Field at the same level must have a unique name."
            end
            seen_names[field.name] = kind
          end
        end

        # Returns the Fields on +descriptor+ paired with their kind label
        # (the human-readable name used in +NameCollisionError+
        # messages, per +docs/code_gen/errors.md § Message convention+). Order is
        # Attributes → MethodAttributes → Associations; the rule is
        # order-independent (first duplicate wins) but a stable scan
        # order keeps the error message deterministic.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @return [Array<Array(Object, String)>] +[field, kind_label]+
        #   pairs
        def fields_with_kinds(descriptor)
          descriptor.attributes.map { |a| [a, "Attribute"] } +
            descriptor.method_attributes.map { |m| [m, "MethodAttribute"] } +
            descriptor.associations.map { |a| [a, "Association"] }
        end
      end
    end
  end
end
