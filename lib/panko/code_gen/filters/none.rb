# frozen_string_literal: true

module SerializersCodeGen
  module Filter
    # No-filter singleton — the common-case fast path per
    # +docs/filters.md § No-filter fast path+. Every Generated Class
    # +serialize_one+ / +serialize_many+ entry calls
    # +Filter.wrap(filters)+; +nil+ and +{}+ collapse to this constant.
    #
    # The interface mirrors the per-cell Filter contract:
    # +drops?(<integer>)+ always returns +false+, +child(<symbol>)+
    # always returns +self+, +none?+ returns +true+. All three are
    # constant-time, allocation-free, and prime YJIT inlining targets.
    #
    # Frozen at module load — the trailing +freeze+ inside the module
    # body below seals the singleton before any caller can observe it.
    # The singleton's identity is the contract: emitted code may compare
    # via +.equal?+ when a future cell ships a +none?+-shortcut
    # dispatcher.
    module None
      # Returns +false+ unconditionally — by definition, the no-filter
      # singleton drops nothing. The integer parameter exists only to
      # keep the call shape identical to the indexed cell that lands in
      # S14.2; it is unread.
      #
      # @param _index [Integer] the Field's codegen-time integer index;
      #   unused on the no-filter path
      # @return [false]
      def self.drops?(_index)
        false
      end

      # Returns the singleton itself — the no-filter path stays
      # allocation-free through nested +Composition+ per
      # +docs/filters.md § Threading through Composition+. The nested
      # Generated Class's +FIELD_INDEX+ is unread on this path because no
      # child cell needs to be materialized — the no-filter sentinel
      # propagates verbatim down the +Composition+ tree.
      #
      # @param _source [Symbol] the Association's Source; unused on the
      #   no-filter path
      # @param _field_index [Hash{Symbol => Integer}] the nested Generated
      #   Class's +FIELD_INDEX+; unused on the no-filter path
      # @return [Filter::None] +self+
      def self.child(_source, _field_index)
        self
      end

      # Returns +true+ — the no-filter sentinel. Future dual-path
      # dispatchers may use this predicate to short-circuit to the
      # unfiltered emit body; today the +indexed × single_path+ verdict
      # from S13 keeps a single emit body, so callers don't branch on it.
      #
      # @return [true]
      def self.none?
        true
      end

      freeze
    end
  end
end
