module Panko::Impl
  class AttributesWriter
    def self.create(object)
      if defined?(ActiveRecord::Base) && object.is_a?(ActiveRecord::Base)
        return ActiveRecordWriter.new
      end

      if object.is_a?(Hash)
        return HashWriter.new
      end

      PlainWriter.new
    end

    class ActiveRecordWriter
      class Context
        attr_reader :attributes_hash, :types, :additional_types, :values

        def initialize(record)
          attributes_set = record.instance_variable_get(:@attributes)
          attributes_hash = attributes_set.instance_variable_get(:@attributes)

          @attributes_hash = (attributes_hash.nil? || attributes_hash.empty?) ? {} : attributes_hash
          @attributes_hash_size = @attributes_hash.size

          @types = attributes_set.instance_variable_get(:@types)
          @additional_types = attributes_set.instance_variable_get(:@additional_types)
          @try_to_read_from_additional_types = !@additional_types.nil? && !@additional_types.empty?

          @values = attributes_set.instance_variable_get(:@values)
          @is_indexed_row = false
          @indexed_row_column_indexes = nil
          @indexed_row_row = nil

          # Check if the values are of type ActiveRecord::Result::IndexedRow
          if defined?(ActiveRecord::Result::IndexedRow) && @values.is_a?(ActiveRecord::Result::IndexedRow)
            @indexed_row_column_indexes = @values.instance_variable_get(:@column_indexes)
            @indexed_row_row = @values.instance_variable_get(:@row)
            @is_indexed_row = true
          end
        end

        # Reads a value from the indexed row
        def read_value_from_indexed_row(member)
          return nil if @indexed_row_column_indexes.nil? || @indexed_row_row.nil?

          column_index = @indexed_row_column_indexes[member]
          return nil if column_index.nil?

          row = @indexed_row_row
          return nil if row.nil?

          row[column_index]
        end

        # Reads the attribute value
        def read_attribute(attribute)
          member = attribute.name
          value = nil

          # If we have a populated attributes_hash
          if !@attributes_hash.nil? && @attributes_hash_size > 0
            attribute_metadata = @attributes_hash[member]
            unless attribute_metadata.nil?
              value = attribute_metadata.instance_variable_get(:@value_before_type_cast)
              attribute.type ||= attribute_metadata.instance_variable_get(:@type)
            end
          end

          # Fallback to reading from values or indexed row
          if value.nil? && !@values.nil?
            value = if @is_indexed_row
              read_value_from_indexed_row(member)
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

          # Typecast the value if necessary
          if !attribute.type.nil? && !value.nil?
            # TODO: handle is_json
            is_json = false
            return Panko._type_cast(attribute.type, value, is_json)
          end

          value
        end
      end

      def write_attributes(object, descriptor, writer)
        # Panko._sd_set_writer(descriptor, object)
        # Panko._write_attributes(object, descriptor, writer)
        attributes_ctx = Context.new(object)
        object_class = object.class

        descriptor.attributes.each do |attribute|
          attribute.invalidate!(object_class)

          value = attributes_ctx.read_attribute(attribute)

          writer.push_value(value, attribute.name_for_serialization)
        end
      end
    end

    class HashWriter
      def write_attributes(object, descriptor, writer)
        descriptor.attributes.each do |attr|
          value = object[attr.name]
          writer.push_value(value, attr.name_for_serialization)
        end
      end
    end

    class PlainWriter
      def write_attributes(object, descriptor, writer)
        descriptor.attributes.each do |attr|
          value = object.public_send(attr.name_sym)
          writer.push_value(value, attr.name_for_serialization)
        end
      end
    end
  end
end
