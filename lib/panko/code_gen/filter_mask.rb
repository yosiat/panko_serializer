# frozen_string_literal: true

module Panko
  module CodeGen
    # Frozen data object that tells generated code which fields to include.
    #
    # Boolean arrays indexed by attribute position in the generated class's
    # constant arrays (+ATTRS+, +MFIELDS+, +HAS_ONE+, +HAS_MANY+).
    # Unfiltered slots use the {INCLUDE_ALL} sentinel (always returns +true+)
    # so generated code can always do +mask[i]+ without a nil check.
    # Per-association override slots use the {NIL_SLOTS} sentinel at the top
    # level (always returns +nil+) so generated code can fall back to the
    # static mask via +ho_masks[i] || @_ho_static_masks[i]+.
    #
    # Computed once per filtered descriptor and cached on it.
    #
    # @example
    #   mask = FilterMask.new(
    #     attrs:         [true, true, false, true],
    #     method_fields: [true],
    #     has_one:       [true],
    #     has_many:      [false]
    #   )
    #   mask.attrs[2]  # => false  (third attribute excluded)
    class FilterMask
      # Boolean array indexed by position in the generated class's +ATTRS+ constant.
      # +true+ means include, +false+ means skip.
      # @return [Array<Boolean>]
      attr_reader :attrs

      # Boolean array indexed by position in +MFIELDS+.
      # +INCLUDE_ALL+ sentinel when unfiltered.
      # @return [Array<Boolean>, INCLUDE_ALL]
      attr_reader :method_fields

      # Boolean array indexed by position in +HAS_ONE+.
      # +INCLUDE_ALL+ sentinel when unfiltered.
      # @return [Array<Boolean>, INCLUDE_ALL]
      attr_reader :has_one

      # Boolean array indexed by position in +HAS_MANY+.
      # +INCLUDE_ALL+ sentinel when unfiltered.
      # @return [Array<Boolean>, INCLUDE_ALL]
      attr_reader :has_many

      # Per-association nested masks for included has_one associations.
      # +nil+ entries mean "include all fields" for that association
      # (the generated code falls back to +@_ho_static_masks[i]+).
      # Never +nil+ at the top level — use {NIL_SLOTS} when no nested overrides
      # exist so generated code can do +ho_masks[i]+ without a safe-nav check.
      # @return [Array<FilterMask, nil>, NIL_SLOTS]
      attr_reader :has_one_masks

      # Per-association nested masks for included has_many associations.
      # See {#has_one_masks} for nil semantics.
      # @return [Array<FilterMask, nil>, NIL_SLOTS]
      attr_reader :has_many_masks

      # @param attrs [Array<Boolean>, INCLUDE_ALL] inclusion mask for plain attributes
      # @param method_fields [Array<Boolean>, INCLUDE_ALL] inclusion mask for method fields
      # @param has_one [Array<Boolean>, INCLUDE_ALL] inclusion mask for has_one associations
      # @param has_many [Array<Boolean>, INCLUDE_ALL] inclusion mask for has_many associations
      # @param has_one_masks [Array<FilterMask, nil>, NIL_SLOTS] nested masks per has_one
      # @param has_many_masks [Array<FilterMask, nil>, NIL_SLOTS] nested masks per has_many
      def initialize(attrs:, method_fields: INCLUDE_ALL, has_one: INCLUDE_ALL, has_many: INCLUDE_ALL,
        has_one_masks: NIL_SLOTS, has_many_masks: NIL_SLOTS)
        @attrs = attrs.freeze
        @method_fields = method_fields.freeze
        @has_one = has_one.freeze
        @has_many = has_many.freeze
        @has_one_masks = has_one_masks.freeze
        @has_many_masks = has_many_masks.freeze
        freeze
      end

      def inspect
        "<Panko::CodeGen::FilterMask attrs=#{@attrs.inspect}>"
      end

      # Singleton object whose +[]+ always returns +true+.
      # Used by {EMPTY} so the generated +if attr_mask[i]+ checks
      # pass without branching on nil.
      INCLUDE_ALL = Class.new {
        def [](*) = true
        def freeze = self
        def frozen? = true
      }.new

      # Singleton object whose +[]+ always returns +nil+.
      # Used in place of +nil+ for +has_one_masks+ / +has_many_masks+ so
      # generated code can write +ho_masks[i] || @_ho_static_masks[i]+
      # without a safe-navigator check.
      NIL_SLOTS = Class.new {
        def [](*) = nil
        def freeze = self
        def frozen? = true
      }.new

      # A FilterMask that includes every field. Passed in place of +nil+
      # so generated code needs only one method (with mask checks) instead
      # of separate filtered/unfiltered variants.
      EMPTY = new(
        attrs: INCLUDE_ALL,
        method_fields: INCLUDE_ALL,
        has_one: INCLUDE_ALL,
        has_many: INCLUDE_ALL,
        has_one_masks: NIL_SLOTS,
        has_many_masks: NIL_SLOTS
      )
    end
  end
end
