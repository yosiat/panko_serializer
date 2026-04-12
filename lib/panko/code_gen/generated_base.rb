# frozen_string_literal: true

module Panko
  module CodeGen
    # Abstract base class for all generated serializer classes.
    #
    # Provides the public serialization API. The {Compiler} defines all
    # write methods on each subclass via +module_eval+:
    #
    # - +_write_one+ — object-type dispatch + method fields + associations
    # - +_write_indexed_cached+ / +_write_indexed_cached_filtered+ — unrolled AR attrs
    # - +_write_method_fields+ / +_write_method_fields_filtered+ — unrolled
    # - +_write_has_one+ / +_write_has_one_filtered+ — unrolled
    # - +_write_has_many+ / +_write_has_many_filtered+ — unrolled
    # - +_write_hash+ / +_write_hash_filtered+ — unrolled Hash attrs
    # - +_write_plain+ / +_write_plain_filtered+ — unrolled PORO attrs
    #
    # Runtime state is held by a single delegate:
    # - +@_ar_writer+ — {ARWriter}, owns parallel caches and AR cold paths
    class GeneratedBase
      class << self
        # Set by the Compiler during class generation.

        # @return [ActiveRecordAttributesWriter]
        # @!attribute [w] _ar_writer
        attr_writer :_ar_writer

        # @return [Array<Panko::Attribute>]
        # @!attribute [w] _attrs
        attr_writer :_attrs

        # @return [Panko::Serializer]
        # @!attribute [w] _serializer
        attr_writer :_serializer
        # Serializes a single object to the given writer.
        #
        # @param object [Object] the object to serialize
        # @param writer [Oj::StringWriter, Panko::ObjectWriter] the output writer
        # @param key [String, nil] JSON key for the object; nil for root
        # @param filter_mask [FilterMask, nil] nil for unfiltered
        # @return [void]
        def serialize_one(object:, writer:, key: nil, filter_mask: nil)
          _serialize_one(object, writer, key, filter_mask: filter_mask)
        end

        # Serializes an array of objects to the given writer.
        #
        # @param objects [Array<Object>] the objects to serialize
        # @param writer [Oj::StringWriter, Panko::ObjectWriter] the output writer
        # @param key [String, nil] JSON key for the array; nil for root
        # @param filter_mask [FilterMask, nil] nil for unfiltered
        # @return [void]
        def serialize_many(objects:, writer:, key: nil, filter_mask: nil)
          _serialize_many(objects, writer, key, filter_mask: filter_mask)
        end

        # Serializes a single object, wrapping it in push_object/pop.
        # Calls +_write_one+ which is generated per-class by the {Compiler}.
        #
        # @param object [Object] the object to serialize
        # @param writer [Oj::StringWriter, Panko::ObjectWriter] the output writer
        # @param key [String, nil] JSON key; nil for root
        # @param filter_mask [FilterMask, nil] nil for unfiltered
        # @return [void]
        def _serialize_one(object, writer, key = nil, filter_mask: nil)
          writer.push_object(key)
          _write_one(object, writer, filter_mask)
          writer.pop
        end

        # Serializes an array of objects, wrapping in push_array/pop.
        # Calls +_write_one+ which is generated per-class by the {Compiler}.
        #
        # @param objects [Array<Object>] the objects to serialize
        # @param writer [Oj::StringWriter, Panko::ObjectWriter] the output writer
        # @param key [String, nil] JSON key; nil for root
        # @param filter_mask [FilterMask, nil] nil for unfiltered
        # @return [void]
        def _serialize_many(objects, writer, key = nil, filter_mask: nil)
          writer.push_array(key)
          if filter_mask
            objects.each do |obj|
              writer.push_object
              _write_one(obj, writer, filter_mask)
              writer.pop
            end
          else
            objects.each do |obj|
              writer.push_object
              _write_one(obj, writer, nil)
              writer.pop
            end
          end
          writer.pop
        end

        # Resolves the AR type for an attribute from the record state's type maps.
        # Called by generated cold-path methods.
        #
        # @param attribute [Panko::Attribute] the attribute to resolve
        # @param rs [Panko::Engine::AttributesWriter::ActiveRecord::RecordState] the record state
        # @return [void]
        def _resolve_type(attribute, rs)
          attribute.type = rs.additional_types[attribute.name] if rs.try_additional
          attribute.type ||= rs.types[attribute.name]
        end

        # Writes a single attribute value using the cached writer,
        # falling back to ValuesWriter. Called by generated cold-path methods.
        #
        # @param attribute [Panko::Attribute] the attribute being written
        # @param value [Object] the raw value
        # @param writer [Oj::StringWriter, Panko::ObjectWriter] the output writer
        # @return [void]
        def _write_value(attribute, value, writer)
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
            Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attribute, value)
          end
        end
      end
    end
  end
end
