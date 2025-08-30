# frozen_string_literal: true

require_relative "../type_cast"

module Panko
  module AttributesWriter
    # Writer for ActiveRecord objects
    class ActiveRecordWriter < Base
      # Cache for attribute metadata per model class
      @attribute_cache = {}
      @indexed_row_class = nil

      class << self
        def attribute_cache_for(record_class)
          @attribute_cache[record_class] ||= {}
        end

        def indexed_row_class
          @indexed_row_class ||= begin
            if defined?(::ActiveRecord::Result::IndexedRow)
              ::ActiveRecord::Result::IndexedRow
            end
          rescue NameError
            nil
          end
        end
      end

      private

      def read_attribute_value(object, attribute, context)
        # Resolve ActiveRecord alias attributes
        resolved_attribute = attribute.resolve_activerecord_alias(object.class)

        # Get cached attribute context for this object
        attributes_ctx = init_context(object)

        # Read the attribute value using the resolved attribute name
        value = read_attribute_from_context(attributes_ctx, resolved_attribute)

        # Apply type casting if needed
        if value
          # Resolve type information for type casting
          type_metadata = resolve_attribute_type(attributes_ctx, resolved_attribute.name_str)
          if type_metadata
            value, _is_json = TypeCast.cast(type_metadata, value)
          end
        end

        value
      end

      def init_context(obj)
        attributes_set = obj.instance_variable_get(:@attributes)
        return {} unless attributes_set

        {
          attributes_hash: attributes_set.instance_variable_get(:@attributes),
          types: attributes_set.instance_variable_get(:@types),
          additional_types: attributes_set.instance_variable_get(:@additional_types),
          values: attributes_set.instance_variable_get(:@values),
          is_indexed_row: indexed_row?(attributes_set.instance_variable_get(:@values)),
          indexed_row_column_indexes: get_indexed_row_column_indexes(attributes_set.instance_variable_get(:@values)),
          indexed_row_row: get_indexed_row_row(attributes_set.instance_variable_get(:@values))
        }
      end

      def indexed_row?(values)
        return false unless values
        self.class.indexed_row_class && values.is_a?(self.class.indexed_row_class)
      end

      def get_indexed_row_column_indexes(values)
        return nil unless indexed_row?(values)
        values.instance_variable_get(:@column_indexes)
      end

      def get_indexed_row_row(values)
        return nil unless indexed_row?(values)
        values.instance_variable_get(:@row)
      end

      def read_attribute_from_context(attributes_ctx, attribute)
        member = attribute.name_str
        value = nil

        # Try to read from attributes_hash first
        if attributes_ctx[:attributes_hash] && !attributes_ctx[:attributes_hash].empty?
          attribute_metadata = attributes_ctx[:attributes_hash][member]
          if attribute_metadata
            value = attribute_metadata.instance_variable_get(:@value_before_type_cast)
            # Note: We can't modify frozen Attribute objects, so type resolution
            # will happen at the TypeCast level instead
          end
        end

        # Fallback to values if not found in attributes_hash
        if value.nil? && attributes_ctx[:values]
          value = if attributes_ctx[:is_indexed_row]
            read_value_from_indexed_row(attributes_ctx, member)
          else
            attributes_ctx[:values][member]
          end
        end

        # For type resolution, we'll handle it at the TypeCast level
        # since we can't modify frozen Attribute objects

        value
      end

      def read_value_from_indexed_row(attributes_ctx, member)
        column_indexes = attributes_ctx[:indexed_row_column_indexes]
        row = attributes_ctx[:indexed_row_row]

        return nil if column_indexes.nil? || row.nil?

        column_index = column_indexes[member]
        return nil if column_index.nil?

        row[column_index.to_i]
      end

      def resolve_attribute_type(attributes_ctx, member)
        # Try additional_types first
        if attributes_ctx[:additional_types] && !attributes_ctx[:additional_types].empty?
          type = attributes_ctx[:additional_types][member]
          return type if type
        end

        # Fallback to types
        if attributes_ctx[:types]
          attributes_ctx[:types][member]
        end
      end
    end
  end
end
