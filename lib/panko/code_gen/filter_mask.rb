# frozen_string_literal: true

module Panko
  module CodeGen
    # Frozen data object that tells generated code which fields to include.
    #
    # Boolean arrays indexed by attribute position in the generated class's
    # constant arrays (+ATTRS+, +MFIELDS+, +HAS_ONE+, +HAS_MANY+).
    # Unfiltered calls pass +nil+ instead of a mask -- zero overhead.
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
      # @return [Array<Boolean>]
      attr_reader :method_fields

      # Boolean array indexed by position in +HAS_ONE+.
      # @return [Array<Boolean>]
      attr_reader :has_one

      # Boolean array indexed by position in +HAS_MANY+.
      # @return [Array<Boolean>]
      attr_reader :has_many

      # Per-association nested masks for included has_one associations.
      # +nil+ entries mean "include all fields" for that association.
      # @return [Array<FilterMask, nil>, nil]
      attr_reader :has_one_masks

      # Per-association nested masks for included has_many associations.
      # +nil+ entries mean "include all fields" for that association.
      # @return [Array<FilterMask, nil>, nil]
      attr_reader :has_many_masks

      # @param attrs [Array<Boolean>] inclusion mask for plain attributes
      # @param method_fields [Array<Boolean>, nil] inclusion mask for method fields
      # @param has_one [Array<Boolean>, nil] inclusion mask for has_one associations
      # @param has_many [Array<Boolean>, nil] inclusion mask for has_many associations
      # @param has_one_masks [Array<FilterMask, nil>, nil] nested masks per has_one
      # @param has_many_masks [Array<FilterMask, nil>, nil] nested masks per has_many
      def initialize(attrs:, method_fields: nil, has_one: nil, has_many: nil,
        has_one_masks: nil, has_many_masks: nil)
        @attrs = attrs.freeze
        @method_fields = method_fields&.freeze
        @has_one = has_one&.freeze
        @has_many = has_many&.freeze
        @has_one_masks = has_one_masks&.freeze
        @has_many_masks = has_many_masks&.freeze
        freeze
      end

      def inspect
        "<Panko::CodeGen::FilterMask attrs=#{@attrs.inspect}>"
      end
    end
  end
end
