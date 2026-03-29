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
    end

    def write_attributes(object, descriptor, writer)
      set_from_record(object)
      object_class = object.class

      attributes = descriptor.attributes
      length = attributes.length
      i = 0

      # Hot path: inline indexed row reading to avoid method call overhead
      if @is_indexed_row
        column_indexes = @indexed_row_column_indexes
        row = @indexed_row_row
        has_hash = @attributes_hash_size > 0
        attrs_hash = @attributes_hash
        types = @types
        additional_types = @additional_types
        try_additional = @try_to_read_from_additional_types

        while i < length
          attribute = attributes[i]
          attribute.invalidate!(object_class)

          member = attribute.name
          value = nil

          if has_hash
            attribute_metadata = attrs_hash[member]
            if attribute_metadata
              value = attribute_metadata.instance_variable_get(:@value_before_type_cast)
              attribute.type ||= attribute_metadata.instance_variable_get(:@type)
            end
          end

          if value.nil?
            column_index = column_indexes[member]
            value = row[column_index] if column_index
          end

          if attribute.type.nil? && value
            if try_additional
              attribute.type = additional_types[member]
            end
            attribute.type ||= types[member]
          end

          ValuesWriter.write(writer, attribute, value)
          i += 1
        end
      else
        while i < length
          attribute = attributes[i]
          attribute.invalidate!(object_class)
          value = read_attribute(attribute)
          ValuesWriter.write(writer, attribute, value)
          i += 1
        end
      end
    end

    private

    def set_from_record(record)
      attributes_set = record._panko_attributes

      attributes_hash = attributes_set._panko_attributes_hash
      if attributes_hash.nil? || attributes_hash.empty?
        @attributes_hash = EMPTY_HASH
        @attributes_hash_size = 0
      else
        @attributes_hash = attributes_hash
        @attributes_hash_size = attributes_hash.size
      end

      @types = attributes_set._panko_types
      @additional_types = attributes_set._panko_additional_types
      @try_to_read_from_additional_types = @additional_types && !@additional_types.empty?

      values = attributes_set._panko_values

      # Check if the values are of type ActiveRecord::Result::IndexedRow
      if PANKO_INDEX_ROW_DEFINED && values.is_a?(ActiveRecord::Result::IndexedRow)
        @indexed_row_column_indexes = values._panko_column_indexes
        @indexed_row_row = values._panko_row
        @is_indexed_row = true
      else
        @indexed_row_column_indexes = nil
        @is_indexed_row = false
        @indexed_row_row = nil
        @values = values
      end
    end

    def read_attribute(attribute)
      member = attribute.name
      value = nil

      if @attributes_hash_size > 0 && !@attributes_hash.nil?
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
        if @try_to_read_from_additional_types
          attribute.type = @additional_types[member]
        end

        attribute.type ||= @types[member]
      end

      value
    end
  end
end
