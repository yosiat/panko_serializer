# frozen_string_literal: true

require_relative "filters/none"

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
  # - +Indexed+ — the winning cell from S13's experiment
  #   (+indexed × single_path+, see
  #   +docs/research/filter_experiments_results.md § 1+). Lands in
  #   S14.2; until then, {wrap} accepts non-empty Hashes and raises
  #   +NotImplementedError+ pointing at S14.2 so callers see a clear
  #   marker rather than a generic raise.
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
    # equivalent to +nil+ at that level — no filtering."). Non-empty
    # Hashes will route to +Filter::Indexed+ once S14.2 lands; until
    # then, this raises +NotImplementedError+ with an S14.2 marker so
    # the deferred path is discoverable from the raise site.
    #
    # @param filters [Hash, nil] the caller-supplied +filters:+ kwarg
    # @return [Filter::None] {NONE} when +filters+ is +nil+ or +{}+
    # @raise [NotImplementedError] when +filters+ is a non-empty Hash —
    #   the indexed cell from S13's verdict ships in S14.2
    def self.wrap(filters)
      return NONE if filters.nil? || filters.empty?
      raise NotImplementedError,
        "Filter.wrap: indexed cell ships in S14.2; non-empty filters: not yet supported (got #{filters.inspect})"
    end
  end
end
