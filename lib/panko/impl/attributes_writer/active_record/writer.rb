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
      @last_record_class = nil
      @types = nil
      @additional_types = nil
      @try_to_read_from_additional_types = false
      @values_writer = ValuesWriter::Writer.new
      @last_invalidated_class = nil
    end

    def write_attributes(object, descriptor, writer)
      set_from_record(object)

      attributes = descriptor.attributes
      length = attributes.length

      # Batch invalidate check: if object class changed, invalidate all attributes once
      object_class = object.class
      if @last_invalidated_class != object_class
        @last_invalidated_class = object_class
        j = 0
        while j < length
          attributes[j].invalidate!(object_class)
          j += 1
        end
      end

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

        if has_hash
          # Slow path: need to check attributes_hash first
          while i < length
            attribute = attributes[i]

            member = attribute.name
            value = nil

            attribute_metadata = attrs_hash[member]
            if attribute_metadata
              value = attribute_metadata.instance_variable_get(:@value_before_type_cast)
              attribute.type ||= attribute_metadata.instance_variable_get(:@type)
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

            key = attribute.name_for_serialization
            if value.nil?
              writer.push_value(nil, key)
            else
              cached = attribute.cached_writer
              if cached
                unless cached.write(value, writer, key)
                  writer.push_value(attribute.type.deserialize(value), key)
                end
              else
                @values_writer.write(writer, attribute, value)
              end
            end
            i += 1
          end
        else
          # Fast path: no attributes_hash, read directly from indexed row
          while i < length
            attribute = attributes[i]

            member = attribute.name
            column_index = column_indexes[member]
            value = column_index ? row[column_index] : nil

            if attribute.type.nil? && value
              if try_additional
                attribute.type = additional_types[member]
              end
              attribute.type ||= types[member]
            end

            key = attribute.name_for_serialization
            if value.nil?
              writer.push_value(nil, key)
            else
              cached = attribute.cached_writer
              if cached
                unless cached.write(value, writer, key)
                  writer.push_value(attribute.type.deserialize(value), key)
                end
              else
                @values_writer.write(writer, attribute, value)
              end
            end
            i += 1
          end
        end
      else
        while i < length
          attribute = attributes[i]
          value = read_attribute(attribute)
          @values_writer.write(writer, attribute, value)
          i += 1
        end
      end
    end

    private

    def set_from_record(record)
      attributes_set = record._panko_attributes
      values = attributes_set._panko_values

      # Fast path for indexed rows from same query (most common case in batch serialization)
      if @is_indexed_row && PANKO_INDEX_ROW_DEFINED && values.is_a?(ActiveRecord::Result::IndexedRow)
        col_indexes = values._panko_column_indexes
        if @indexed_row_column_indexes.equal?(col_indexes)
          # Same query result - only need to update the row
          @indexed_row_row = values._panko_row
          return
        end
      end

      # Full initialization path
      attributes_hash = attributes_set._panko_attributes_hash
      if attributes_hash.nil? || attributes_hash.empty?
        @attributes_hash = EMPTY_HASH
        @attributes_hash_size = 0
      else
        @attributes_hash = attributes_hash
        @attributes_hash_size = attributes_hash.size
      end

      # Cache types/additional_types per model class
      record_class = record.class
      if @last_record_class != record_class
        @last_record_class = record_class
        @types = attributes_set._panko_types
        @additional_types = attributes_set._panko_additional_types
        @try_to_read_from_additional_types = @additional_types && !@additional_types.empty?
      end

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
