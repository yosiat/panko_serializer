# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Builds the per-Generated-Class +FIELD_INDEX+ map. Codegen-time
    # +Symbol → Integer+ assignment over a +Descriptor+'s Fields in the
    # canonical declared order — Attributes, then Method Attributes,
    # then Associations — per +docs/code_gen/filters.md § Threading through
    # Composition+. Mode-agnostic (the same map is emitted into
    # +<Name>_JSON+ and +<Name>_Hash+) so JSON/Hash parity holds at the
    # filter contract per the parent S14 PRD.
    #
    # The integers are baked into:
    #
    # - The class's +FIELD_INDEX = {...}.freeze+ constant — read by
    #   +Filter::Indexed+ in S14.2 to map caller-supplied symbols
    #   (+only:+/+except:+) into bit positions / array indices.
    # - Each Field emitter's +unless filters.drops?(<integer>) ... end+
    #   wrapper — pinned at codegen so the runtime hot path is one
    #   +Integer#[]+ (or +Array#[]+) lookup, not a per-Field Hash probe.
    module FieldIndex
      module_function

      # Returns the +Symbol → Integer+ map for +descriptor+'s Fields in
      # declared order: Attributes (0..n_attrs-1), then Method
      # Attributes (n_attrs..n_attrs+n_method_attrs-1), then
      # Associations (n_attrs+n_method_attrs..). Insertion order is
      # preserved by Ruby's +Hash+ so the produced map iterates in the
      # same order the constant emits.
      #
      # Consumers MUST look up integers by the field's filter key —
      # +field.name+ for Attributes and Method Attributes,
      # +association.source+ for Associations — not by iteration
      # position; the +unless filters.drops?(N)+ wrappers in emitted
      # code bake the same fetch, so the parity between this map and
      # the wrappers can't drift on ordering. Pinned by
      # +spec/generators/field_index_spec.rb+.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @return [Hash{Symbol => Integer}]
      def build(descriptor)
        index = {}
        i = 0
        descriptor.attributes.each do |attribute|
          index[attribute.name] = i
          i += 1
        end
        descriptor.method_attributes.each do |method_attribute|
          index[method_attribute.name] = i
          i += 1
        end
        # Associations key by +source+ (the declared relation), not +name+
        # (the output key): filter callers address an aliased association by
        # the name it was declared with — matching the sub-filter descent key
        # (+Filter#child(:<source>)+) and Panko 0.8.5. Value Fields keep the
        # +name+ key, mirroring 0.8.5's alias-keyed attribute filtering.
        descriptor.associations.each do |association|
          index[association.source] = i
          i += 1
        end
        index
      end

      # Returns the Ruby source literal for the +FIELD_INDEX+ constant,
      # without the trailing +.freeze+. Uses the symbol-shorthand
      # +{name: 0, ...}+ form — every Field's +name+ is a +Symbol+
      # validated at +Data.new+, and the canonical fixtures all use
      # identifier-style names. Empty Hash emits +{}+.
      #
      # @param field_index [Hash{Symbol => Integer}] from {.build}
      # @return [String] e.g. +"{id: 0, title: 1}"+
      def to_hash_literal(field_index)
        return "{}" if field_index.empty?
        pairs = field_index.map { |name, idx| "#{name}: #{idx}" }
        "{#{pairs.join(", ")}}"
      end
    end
  end
end
