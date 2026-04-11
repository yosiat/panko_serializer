# frozen_string_literal: true

module Panko::Engine::AttributesWriter::ActiveRecord
  class RecordState
    # The column name → array index map for the current IndexedRow.
    # Why: allows O(1) lookup of a field's position in the raw row array,
    # avoiding AR's attribute hash lookup on every serialized field.
    # @return [Hash{String => Integer}, nil]
    attr_reader :column_indexes

    # The raw row array from the current IndexedRow.
    # Why: direct indexed access to query result data, bypassing AR's
    # ActiveModel::Attribute wrappers entirely.
    # @return [Array, nil]
    attr_reader :row

    # Whether the current record is backed by an IndexedRow (Rails 8+).
    # Why: gates the entire fast-path branch in Writer#write_attributes.
    # @return [Boolean]
    attr_reader :is_indexed_row

    # The dirty/mutated attributes hash (attribute name → ActiveModel::Attribute).
    # Why: changed attributes take priority over raw row values; must be checked
    # before falling back to the indexed row.
    # @return [Hash{String => ActiveModel::Attribute}]
    attr_reader :attributes_hash

    # Cached boolean: whether +attributes_hash+ is non-empty.
    # Why: avoids repeated +#empty?+ calls on the hot path.
    # @return [Boolean]
    attr_reader :has_attributes_hash

    # The schema type map (attribute name → ActiveModel::Type::Value) for the current class.
    # Why: needed to deserialize raw row values into Ruby types (e.g. date strings → Date).
    # Refreshed only when the record class changes.
    # @return [Hash{String => ActiveModel::Type::Value}, nil]
    attr_reader :types

    # Fallback type map for attributes declared via the AR +attribute+ API (custom types).
    # Why: Rails stores these separately from the main column types; we must check both.
    # @return [Hash{String => ActiveModel::Type::Value}, nil]
    attr_reader :additional_types

    # Cached boolean: whether +additional_types+ is non-nil and non-empty.
    # Why: avoids repeated nil? + empty? checks on every field in the hot path.
    # @return [Boolean]
    attr_reader :try_additional

    # The non-indexed attribute values hash (used on Rails 7.x without IndexedRow).
    # Why: Rails 7.x query results expose values as a Hash rather than an indexed array;
    # this is the fallback for those versions.
    # @return [Hash{String => Object}, nil]
    attr_reader :values

    # The ActiveRecord class of the most recently set up record.
    # Why: Writer needs this to look up +attribute_aliases+ when the class changes.
    # @return [Class, nil]
    attr_reader :last_record_class

    def initialize
      @column_indexes = nil
      @row = nil
      @is_indexed_row = false
      @attributes_hash = EMPTY_HASH
      @has_attributes_hash = false
      @types = nil
      @additional_types = nil
      @try_additional = false
      @values = nil
      @last_record_class = nil
    end

    # Sets up state for the given +object+ before attribute writing begins.
    # Handles both the IndexedRow fast path and the full initialization path.
    # Returns true if the record class changed since the last call (caller must
    # invalidate attributes and re-resolve AR aliases when this is true).
    #
    # @param object [ActiveRecord::Base] the record being serialized
    # @return [Boolean] whether the record class changed
    def setup(object)
      attributes_set = object._panko_attributes
      values = attributes_set._panko_values

      # IndexedRow fast path: if column_indexes reference is identical, we are
      # in the same query batch and only the row data changed.
      # The is_a? guard handles the case where a reused RecordState (e.g. via
      # thread-local descriptor caching) previously saw an IndexedRow but is
      # now called with a non-indexed object.
      if @is_indexed_row && values.is_a?(::ActiveRecord::Result::IndexedRow) && @column_indexes.equal?(values._panko_column_indexes)
        @row = values._panko_row
        return false
      end

      # Full initialization path
      attributes_hash = attributes_set._panko_attributes_hash
      if attributes_hash.nil? || attributes_hash.empty?
        @attributes_hash = EMPTY_HASH
        @has_attributes_hash = false
      else
        @attributes_hash = attributes_hash
        @has_attributes_hash = true
      end

      record_class = object.class
      class_changed = @last_record_class != record_class
      if class_changed
        @last_record_class = record_class
        @types = attributes_set._panko_types
        @additional_types = attributes_set._panko_additional_types
        @try_additional = !@additional_types.nil? && !@additional_types.empty?
      end

      if PANKO_INDEX_ROW_DEFINED && values.is_a?(::ActiveRecord::Result::IndexedRow)
        @column_indexes = values._panko_column_indexes
        @row = values._panko_row
        @is_indexed_row = true
      else
        @column_indexes = nil
        @is_indexed_row = false
        @row = nil
        @values = values
      end

      class_changed
    end

    # Reads the value for +attribute+ from the non-indexed attribute set.
    # Used on Rails 7.x where query results are not IndexedRow-backed.
    # Checks the dirty attributes hash first, then falls back to the values hash.
    #
    # @param attribute [Panko::Attribute] the attribute to read
    # @return [Object, nil] the raw attribute value
    def read_attribute(attribute)
      member = attribute.name
      value = nil

      if @has_attributes_hash
        attribute_metadata = @attributes_hash[member]
        unless attribute_metadata.nil?
          value = attribute_metadata.instance_variable_get(:@value_before_type_cast)
          attribute.type ||= attribute_metadata.instance_variable_get(:@type)
        end
      end

      if value.nil? && !@values.nil?
        value = @values[member]
      end

      if attribute.type.nil? && !value.nil?
        if @try_additional
          attribute.type = @additional_types[member]
        end
        attribute.type ||= @types[member]
      end

      value
    end
  end
end
