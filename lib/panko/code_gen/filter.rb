# frozen_string_literal: true

require_relative "filters/none"
require_relative "filters/indexed"

module Panko::CodeGen
  module Filter
    # Validates every level here, once per call, so the generated per-record
    # bodies need no validation branches.
    def self.wrap(filters, field_index = nil)
      return None if filters.nil? || filters.empty?
      validate_no_only_except_co_supply!(filters)
      raise ArgumentError, "Filter.wrap: a non-empty filters Hash requires a field_index (the Generated Class's FIELD_INDEX)" if field_index.nil?
      Indexed.build(filters, field_index)
    end

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
