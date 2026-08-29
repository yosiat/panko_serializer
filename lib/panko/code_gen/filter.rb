# frozen_string_literal: true

require_relative "filters/none"
require_relative "filters/indexed"

module Panko::CodeGen
  # Public-facing namespace for the +Filter+ family. {Filter.wrap} is
  # the single entry point used at the top of every Generated Class's
  # +serialize_one+ / +serialize_many+; it normalizes the
  # caller-supplied +filters:+ Hash into a +Filter+ object exposing the
  # +drops?(<integer>)+ / +child(<symbol>)+ contract.
  #
  # Two cells exist in this slice:
  #
  # - {None} — the no-filter singleton; +nil+ and +{}+ map
  #   here. +drops?+ returns +false+, +child+ returns +self+.
  #   Allocation-free, frozen at module load.
  # - {Indexed} — the indexed cell, backed by a Boolean
  #   Array over the Generated Class's +FIELD_INDEX+ positions.
  module Filter
    # Normalizes the caller-supplied +filters:+ kwarg into a Filter
    # object satisfying the +drops?+ / +child+ contract.
    # +nil+ and +{}+ collapse to {None} ("Empty Hash +{}+ at a level is
    # equivalent to +nil+ at that level — no filtering."). A non-empty
    # Hash routes to {Indexed.build} against +field_index+ — the
    # per-Generated-Class +FIELD_INDEX+ map emitted by
    # {Generators::FieldIndex}.
    #
    # +field_index+ is unread on the +nil+ / +{}+ paths, so emitted
    # code can pass +FIELD_INDEX+ unconditionally without paying a
    # constant-lookup cost when no filtering is in effect (the lookup
    # is one constant resolution per call regardless).
    #
    # Recursively walks +filters+ before delegating to {Indexed.build}
    # and raises +ArgumentError+ at the first level (depth-first) that
    # carries both +:only+ and +:except+ keys. Validation runs once per
    # +serialize_*+ call so the emitted +_write_one+ / +_to_hash+ bodies
    # stay free of validation branches.
    #
    # @param filters [Hash, nil] the caller-supplied +filters:+ kwarg
    # @param field_index [Hash{Symbol => Integer}, nil] the
    #   per-Generated-Class +FIELD_INDEX+ map; required when +filters+
    #   is a non-empty Hash
    # @return [Filter::None, Filter::Indexed::Array]
    # @raise [ArgumentError] when +filters+ is a non-empty Hash but
    #   +field_index+ is +nil+ — the indexed cell needs the per-class
    #   field map to translate symbols to integer positions
    # @raise [ArgumentError] when any level of +filters+ supplies both
    #   +:only+ and +:except+
    def self.wrap(filters, field_index = nil)
      return None if filters.nil? || filters.empty?
      validate_no_only_except_co_supply!(filters)
      raise ArgumentError, "Filter.wrap: a non-empty filters Hash requires a field_index (the Generated Class's FIELD_INDEX)" if field_index.nil?
      Indexed.build(filters, field_index)
    end

    # Walks +hash+ depth-first and raises +ArgumentError+ at the first
    # level that has both +:only+ and +:except+ keys. Recurses into any
    # value that is itself a +Hash+ (Association sub-filters) and
    # ignores non-Hash values (the +:only+ / +:except+ Arrays
    # themselves, plus forward-compat unknown-shape values that are
    # silently ignored).
    #
    # Module-private: only {wrap} should call this. Pinned at module
    # scope (rather than inlined) so the recursion-around-Hash-values
    # contract is testable via {Filter.wrap} from one site.
    #
    # @param hash [Hash] a level of the caller-supplied +filters:+
    # @return [void]
    # @raise [ArgumentError] when +hash+ has both +:only+ and +:except+
    def self.validate_no_only_except_co_supply!(hash)
      if hash.key?(:only) && hash.key?(:except)
        raise ArgumentError,
          "filters: cannot supply both :only and :except at the same level " \
          "(got only: #{hash[:only].inspect}, except: #{hash[:except].inspect})"
      end
      hash.each_value do |value|
        validate_no_only_except_co_supply!(value) if value.is_a?(Hash)
      end
    end
    private_class_method :validate_no_only_except_co_supply!
  end
end
