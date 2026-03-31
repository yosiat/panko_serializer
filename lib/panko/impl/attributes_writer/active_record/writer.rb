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
      @types_resolved = false
      @column_index_cache = nil  # Pre-computed column indices per attribute
    end

    def write_attributes(object, descriptor, writer)
      attributes = descriptor.attributes
      length = attributes.length

      # Inline fast path of set_from_record to avoid method call overhead
      attributes_set = object._panko_attributes
      values = attributes_set._panko_values
      if @is_indexed_row && @indexed_row_column_indexes.equal?(values._panko_column_indexes)
        # Same query batch: same column_indexes implies same class
        @indexed_row_row = values._panko_row
      else
        _set_from_record_full(object, attributes_set, values)

        # Check if class changed (only on slow path - first record or schema change)
        object_class = object.class
        if @last_invalidated_class != object_class
          @last_invalidated_class = object_class
          @types_resolved = false
          @column_index_cache = nil
          aliases_hash = object_class.attribute_aliases
          j = 0
          while j < length
            attr = attributes[j]
            attr.invalidate!
            unless aliases_hash.empty?
              aliased_value = aliases_hash[attr.name]
              if aliased_value.present?
                attr.alias_name = attr.name
                attr.name = aliased_value
              end
            end
            j += 1
          end
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
        elsif @types_resolved
          # Fast path: no attributes_hash, read directly from indexed row
          col_cache = @column_index_cache
          key_cache = @key_cache
          writer_cache = @writer_cache
          direct_cache = @direct_cache
          unless col_cache
            col_cache = Array.new(length)
            key_cache = Array.new(length)
            writer_cache = Array.new(length)
            direct_cache = Array.new(length)
            j = 0
            while j < length
              attr = attributes[j]
              col_cache[j] = column_indexes[attr.name]
              key_cache[j] = attr.name_for_serialization
              cw = attr.cached_writer
              writer_cache[j] = cw
              # String and integer writers just push_value directly - skip method call
              direct_cache[j] = cw.is_a?(ValuesWriter::StringWriter) || cw.is_a?(ValuesWriter::IntegerWriter) || cw.is_a?(ValuesWriter::FloatWriter) || cw.is_a?(ValuesWriter::BooleanWriter)
              j += 1
            end
            @column_index_cache = col_cache
            @key_cache = key_cache
            @writer_cache = writer_cache
            @direct_cache = direct_cache
          end

          while i < length
            value = row[col_cache[i]]

            if direct_cache[i]
              # Direct push for string/integer/float/boolean - push_value handles nil natively
              writer.push_value(value, key_cache[i])
            elsif value.nil?
              writer.push_value(nil, key_cache[i])
            else
              writer_cache[i].write(value, writer, key_cache[i])
            end
            i += 1
          end
        # Ultra-fast path: all types and cached_writers are already resolved
        # Use pre-computed caches
        else
          # First pass: need to resolve types and cache writers
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
          @types_resolved = true
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

    def _set_from_record_full(record, attributes_set, values)
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
