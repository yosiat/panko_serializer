# frozen_string_literal: true

require_relative "filters/none"
require_relative "filters/indexed"

module SerializersCodeGen
  # Public-facing namespace for the +Filter+ family per
  # +docs/filters.md+. {Filter.wrap} is the single entry point used at
  # the top of every Generated Class's +serialize_one+ /
  # +serialize_many+; it normalizes the caller-supplied +filters:+ Hash
  # into a +Filter+ object exposing the +drops?(<integer>)+ /
  # +child(<symbol>)+ / +none?+ contract.
  #
  # Two cells exist in this slice:
  #
  # - {None} — the no-filter singleton ({NONE}); +nil+ and +{}+ map
  #   here. +drops?+ returns +false+, +child+ returns +self+, +none?+
  #   returns +true+. Allocation-free, frozen at module load.
  # - {Indexed} — the winning cell from S13's experiment
  #   (+indexed × single_path+, see
  #   +docs/research/filter_experiments_results.md § 1+). Lifted from
  #   +docs/research/filter_experiments_bench.rb+ (lines 281–433).
  #   Picks {Indexed::Bits} (Integer bit-mask) when the Generated
  #   Class's +FIELD_INDEX+ has +<= INDEXED_BITS_THRESHOLD+ entries,
  #   {Indexed::Array} (Boolean Array) otherwise.
  module Filter
    # The no-filter singleton — frozen reference to the {Filter::None}
    # module. Emitted code receives this instance whenever the caller
    # passed +nil+ or +{}+, so the no-filter hot path pays zero filter
    # allocations per +docs/filters.md § No-filter fast path+.
    NONE = None

    # Normalizes the caller-supplied +filters:+ kwarg into a Filter
    # object satisfying the +drops?+ / +child+ / +none?+ contract.
    # +nil+ and +{}+ collapse to {NONE} per
    # +docs/filters.md § Public shape+ ("Empty Hash +{}+ at a level is
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
    # @param filters [Hash, nil] the caller-supplied +filters:+ kwarg
    # @param field_index [Hash{Symbol => Integer}, nil] the
    #   per-Generated-Class +FIELD_INDEX+ map; required when +filters+
    #   is a non-empty Hash
    # @return [Filter::None, Filter::Indexed::Bits, Filter::Indexed::Array]
    # @raise [ArgumentError] when +filters+ is a non-empty Hash but
    #   +field_index+ is +nil+ — the indexed cell needs the per-class
    #   field map to translate symbols to integer positions
    def self.wrap(filters, field_index = nil)
      return NONE if filters.nil? || filters.empty?
      raise ArgumentError, "Filter.wrap: a non-empty filters Hash requires a field_index (the Generated Class's FIELD_INDEX)" if field_index.nil?
      Indexed.build(filters, field_index)
    end
  end
end
