# frozen_string_literal: true

require_relative "context"
require_relative "record_state"
require_relative "values_writer/writer"

module Panko::Engine::AttributesWriter::ActiveRecord
  # Writes serialized attributes for ActiveRecord objects to an Oj::StringWriter.
  #
  # Selects one of four write strategies per call based on record state:
  #
  # 1. *Indexed + dirty attributes* (+write_indexed_with_hash+) —
  #    The record has mutated attributes that override raw row values.
  #    Must check the dirty-attributes hash before falling back to the indexed row.
  #
  # 2. *Indexed + cached* (+write_indexed_cached+) —
  #    Types are resolved and per-attribute caches are built. Reads values
  #    directly from the raw row array with zero per-attribute branching.
  #
  # 3. *Indexed + first pass* (+write_indexed_first_pass+) —
  #    First time seeing this set of attributes. Resolves types, caches writers,
  #    then builds the column/key/writer caches for subsequent calls.
  #
  # 4. *Non-indexed* (+write_non_indexed+) —
  #    Rails 7.x fallback where query results are a Hash, not an IndexedRow.
  class Writer
    def initialize
      @record_state = RecordState.new
      @values_writer = ValuesWriter::Writer.new
      @last_invalidated_class = nil
      @types_resolved = false

      # Per-attribute caches built after the first pass. Each is an Array
      # of length == attributes.length, indexed in lockstep:
      #   @column_index_cache[i] — column index in the raw row for attribute i
      #   @key_cache[i]          — JSON key (name or alias) for attribute i
      #   @writer_cache[i]       — cached ValuesWriter instance for attribute i
      #   @direct_cache[i]       — true if the writer supports direct push_value
      @column_index_cache = nil
      @key_cache = nil
      @writer_cache = nil
      @direct_cache = nil
    end

    # Writes all attributes from +descriptor+ for +object+ into +writer+.
    #
    # @param object [ActiveRecord::Base] the record being serialized
    # @param descriptor [Panko::SerializationDescriptor] pre-computed attribute metadata
    # @param writer [Oj::StringWriter] the JSON output target
    # @return [void]
    def write_attributes(object, descriptor, writer)
      attributes = descriptor.attributes
      class_changed = @record_state.setup(object)

      handle_class_change(attributes) if class_changed

      if @record_state.is_indexed_row
        if @record_state.has_attributes_hash
          write_indexed_with_hash(attributes, writer)
        elsif @types_resolved
          write_indexed_cached(attributes, writer)
        else
          write_indexed_first_pass(attributes, writer)
        end
      else
        write_non_indexed(attributes, writer)
      end
    end

    private

    # Invalidates cached types/writers and resolves AR column aliases
    # when the record class changes between calls.
    #
    # @param attributes [Array<Panko::Attribute>] the attribute list to invalidate
    # @return [void]
    def handle_class_change(attributes)
      @types_resolved = false
      @column_index_cache = nil

      aliases_hash = @record_state.last_record_class.attribute_aliases
      has_aliases = !aliases_hash.empty?

      i = 0
      length = attributes.length
      while i < length
        attr = attributes[i]
        attr.invalidate!
        if has_aliases
          aliased_value = aliases_hash[attr.name]
          if aliased_value.present?
            attr.alias_name = attr.name
            attr.name = aliased_value
          end
        end
        i += 1
      end
    end

    # Resolves the AR type for +attribute+ from the record state's type maps.
    # Sets +attribute.type+ as a side effect.
    #
    # @param attribute [Panko::Attribute] the attribute to resolve
    # @return [void]
    def resolve_type(attribute)
      if @record_state.try_additional
        attribute.type = @record_state.additional_types[attribute.name]
      end
      attribute.type ||= @record_state.types[attribute.name]
    end

    # Writes a single attribute +value+ to +writer+ using the cached writer
    # if available, falling back to the general values writer.
    #
    # @param attribute [Panko::Attribute] the attribute being written
    # @param value [Object] the raw value from the database row
    # @param writer [Oj::StringWriter] the JSON output target
    # @return [void]
    def write_value(attribute, value, writer)
      key = attribute.name_for_serialization

      if value.nil?
        writer.push_value(nil, key)
        return
      end

      cached = attribute.cached_writer
      if cached
        unless cached.write(value, writer, key)
          writer.push_value(attribute.type.deserialize(value), key)
        end
      else
        @values_writer.write(writer, attribute, value)
      end
    end

    # Slow path: the record has dirty/mutated attributes that must be checked
    # before falling back to the raw indexed row.
    #
    # @param attributes [Array<Panko::Attribute>] the attribute list
    # @param writer [Oj::StringWriter] the JSON output target
    # @return [void]
    def write_indexed_with_hash(attributes, writer)
      column_indexes = @record_state.column_indexes
      row = @record_state.row
      attrs_hash = @record_state.attributes_hash

      i = 0
      length = attributes.length
      while i < length
        attribute = attributes[i]
        member = attribute.name

        # Dirty attributes take priority over raw row values
        value = nil
        attribute_metadata = attrs_hash[member]
        if attribute_metadata
          value = attribute_metadata.instance_variable_get(:@value_before_type_cast)
          attribute.type ||= attribute_metadata.instance_variable_get(:@type)
        end

        # Fall back to raw indexed row
        if value.nil?
          column_index = column_indexes[member]
          value = row[column_index] if column_index
        end

        resolve_type(attribute) if attribute.type.nil? && value
        write_value(attribute, value, writer)

        i += 1
      end
    end

    # Ultra-fast path: all types are resolved and per-attribute caches are built.
    # Reads values directly from the raw row array with minimal branching.
    #
    # @param attributes [Array<Panko::Attribute>] the attribute list
    # @param writer [Oj::StringWriter] the JSON output target
    # @return [void]
    def write_indexed_cached(attributes, writer)
      build_column_caches(attributes) unless @column_index_cache

      row = @record_state.row
      col_cache = @column_index_cache
      key_cache = @key_cache
      writer_cache = @writer_cache
      direct_cache = @direct_cache

      i = 0
      length = attributes.length
      while i < length
        value = row[col_cache[i]]

        if direct_cache[i]
          # String/integer/float/boolean writers — push_value handles nil natively
          writer.push_value(value, key_cache[i])
        elsif value.nil?
          writer.push_value(nil, key_cache[i])
        else
          writer_cache[i].write(value, writer, key_cache[i])
        end
        i += 1
      end
    end

    # First-pass path: resolves types and caches writers for each attribute,
    # then eagerly builds the column/key/writer caches for subsequent calls.
    #
    # @param attributes [Array<Panko::Attribute>] the attribute list
    # @param writer [Oj::StringWriter] the JSON output target
    # @return [void]
    def write_indexed_first_pass(attributes, writer)
      column_indexes = @record_state.column_indexes
      row = @record_state.row

      i = 0
      length = attributes.length
      while i < length
        attribute = attributes[i]

        column_index = column_indexes[attribute.name]
        value = column_index ? row[column_index] : nil

        resolve_type(attribute) if attribute.type.nil? && value
        write_value(attribute, value, writer)

        i += 1
      end

      @types_resolved = true
      build_column_caches(attributes)
    end

    # Rails 7.x fallback: reads attributes through RecordState#read_attribute
    # which handles non-indexed (Hash-based) attribute sets.
    #
    # @param attributes [Array<Panko::Attribute>] the attribute list
    # @param writer [Oj::StringWriter] the JSON output target
    # @return [void]
    def write_non_indexed(attributes, writer)
      i = 0
      length = attributes.length
      while i < length
        attribute = attributes[i]
        value = @record_state.read_attribute(attribute)
        @values_writer.write(writer, attribute, value)
        i += 1
      end
    end

    # Builds the per-attribute parallel caches used by the ultra-fast path.
    # Called once after the first pass resolves all types.
    #
    # @param attributes [Array<Panko::Attribute>] the attribute list
    # @return [void]
    def build_column_caches(attributes)
      column_indexes = @record_state.column_indexes
      length = attributes.length

      col_cache = Array.new(length)
      key_cache = Array.new(length)
      writer_cache = Array.new(length)
      direct_cache = Array.new(length)

      i = 0
      while i < length
        attr = attributes[i]
        col_cache[i] = column_indexes[attr.name]
        key_cache[i] = attr.name_for_serialization
        cw = attr.cached_writer
        writer_cache[i] = cw
        direct_cache[i] = cw&.nil_safe_push? || false
        i += 1
      end

      @column_index_cache = col_cache
      @key_cache = key_cache
      @writer_cache = writer_cache
      @direct_cache = direct_cache
    end
  end
end
