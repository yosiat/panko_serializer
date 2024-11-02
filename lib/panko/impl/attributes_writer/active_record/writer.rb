# frozen_string_literal: true

require_relative "context"
require_relative "values_writer/writer"

module Panko::Impl::AttributesWriter::ActiveRecord
  class Writer
    def initialize
      @attributes_hash = EMPTY_HASH
      @attributes_hash_size = 0

      @indexed_row_column_indexes = nil
      @is_indexed_row = false
      @indexed_row_row = nil
      @attribute_indices = []
    end

    def write_attributes(object, descriptor, writer)
      set_from_record(object)
      object_class = object.class

      length = descriptor.attributes.length
      i = 0
      while i < length
        attribute = descriptor.attributes[i]

        attribute.invalidate!(object_class)

        value = read_attribute(attribute, i)

        ValuesWriter.write(writer, attribute, value)

        i += 1
      end
    end

    private

    def set_from_record(record)
      attributes_set = record._panko_attributes

      attributes_hash = attributes_set._panko_attributes_hash
      if attributes_hash&.empty?
        @attributes_hash = EMPTY_HASH
        @attributes_hash_size = 0
      else
        @attributes_hash = attributes_hash
        @attributes_hash_size = attributes_hash.size
      end

      @types = attributes_set._panko_types
      @additional_types = attributes_set._panko_additional_types
      @try_to_read_from_additional_types = !@additional_types.nil? && !@additional_types.empty?

      @values = attributes_set._panko_values

      # Check if the values are of type ActiveRecord::Result::IndexedRow
      if PANKO_INDEX_ROW_DEFINED && @values.is_a?(ActiveRecord::Result::IndexedRow)
        @indexed_row_column_indexes = @values._panko_column_indexes
        @indexed_row_row = @values._panko_row
        @is_indexed_row = true
      else
        @indexed_row_column_indexes = nil
        @is_indexed_row = false
        @indexed_row_row = nil
      end
    end

    # Reads a value from the indexed row
    def read_value_from_indexed_row(member, index)
      return nil if @indexed_row_column_indexes.nil? || @indexed_row_row.nil?

      column_index = @attribute_indices[index]
      if column_index.nil?
        column_index = @indexed_row_column_indexes[member]
        @attribute_indices[index] = column_index
      end
      return nil if column_index.nil?

      row = @indexed_row_row
      return nil if row.nil?

      row[column_index]
    end

    # Reads the attribute value
    def read_attribute(attribute, index)
      member = attribute.name
      value = nil

      # If we have a populated attributes_hash
      if @attributes_hash_size > 0 && !@attributes_hash.nil?
        attribute_metadata = @attributes_hash[member]
        unless attribute_metadata.nil?
          value = attribute_metadata.instance_variable_get(:@value_before_type_cast)
          attribute.type ||= attribute_metadata.instance_variable_get(:@type)
        end
      end

      # Fallback to reading from values or indexed row
      if value.nil? && !@values.nil?
        value = if @is_indexed_row
          read_value_from_indexed_row(member, index)
        else
          @values[member]
        end
      end

      # Fetch the type if not yet set
      if attribute.type.nil? && !value.nil?
        if @try_to_read_from_additional_types
          attribute.type = @additional_types[member]
        end

        attribute.type ||= @types[member]
      end

      value
    end
  end
end
