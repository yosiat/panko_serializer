# frozen_string_literal: true

require_relative "context"
require_relative "record_state"
require_relative "values_writer/writer"

module Panko::Impl::AttributesWriter::ActiveRecord
  class Writer
    def initialize
      @record_state = RecordState.new
      @values_writer = ValuesWriter::Writer.new
      @last_invalidated_class = nil
      @types_resolved = false
      @column_index_cache = nil
    end

    def write_attributes(object, descriptor, writer)
      attributes = descriptor.attributes
      length = attributes.length

      class_changed = @record_state.setup(object)

      if class_changed
        @types_resolved = false
        @column_index_cache = nil
        aliases_hash = object.class.attribute_aliases
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

      i = 0

      # Hot path: inline indexed row reading to avoid method call overhead
      if @record_state.is_indexed_row
        column_indexes = @record_state.column_indexes
        row = @record_state.row
        has_hash = @record_state.has_attributes_hash
        attrs_hash = @record_state.attributes_hash
        types = @record_state.types
        additional_types = @record_state.additional_types
        try_additional = @record_state.try_additional

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
          value = @record_state.read_attribute(attribute)
          @values_writer.write(writer, attribute, value)
          i += 1
        end
      end
    end
  end
end
