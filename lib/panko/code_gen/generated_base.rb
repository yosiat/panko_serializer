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

        # @return [Array<Panko::Association>]
        # @!attribute [w] _has_one_assocs
        attr_writer :_has_one_assocs

        # @return [Array<Panko::Association>]
        # @!attribute [w] _has_many_assocs
        attr_writer :_has_many_assocs

        # Per-association static sub-masks for has_one. Each element is
        # a FilterMask (when the association has a static filter like
        # +has_one :foo, only: [:name]+) or nil (no static filtering).
        # @return [Array<FilterMask?, nil>]
        # @!attribute [w] _ho_static_masks
        attr_writer :_ho_static_masks

        # Per-association static sub-masks for has_many.
        # @return [Array<FilterMask?, nil>]
        # @!attribute [w] _hm_static_masks
        attr_writer :_hm_static_masks
        # Serializes a single object to the given writer.
        #
        # @param object [Object] the object to serialize
        # @param writer [Oj::StringWriter] the output writer
        # @param key [String, nil] JSON key for the object; nil for root
        # @param filter_mask [FilterMask, nil] nil for unfiltered
        # @return [void]
        def serialize_one(object:, writer:, key: nil, filter_mask: nil, context: nil)
          _serialize_one(object, writer, key, filter_mask: filter_mask, context: context)
        end

        # Serializes an array of objects to the given writer.
        #
        # @param objects [Array<Object>] the objects to serialize
        # @param writer [Oj::StringWriter] the output writer
        # @param key [String, nil] JSON key for the array; nil for root
        # @param filter_mask [FilterMask, nil] nil for unfiltered
        # @param context [SerializationContext, nil] context/scope for method fields
        # @return [void]
        def serialize_many(objects:, writer:, key: nil, filter_mask: nil, context: nil)
          _serialize_many(objects, writer, key, filter_mask: filter_mask, context: context)
        end

        # Serializes a single object, wrapping it in push_object/pop.
        # Calls +_write_one+ which is generated per-class by the {Compiler}.
        #
        # @param object [Object] the object to serialize
        # @param writer [Oj::StringWriter] the output writer
        # @param key [String, nil] JSON key; nil for root
        # @param filter_mask [FilterMask, nil] nil for unfiltered
        # @param context [SerializationContext, nil] context/scope for method fields
        # @return [void]
        def _serialize_one(object, writer, key = nil, filter_mask: nil, context: nil)
          writer.push_object(key)
          _write_one(object, writer, filter_mask, context)
          writer.pop
        end

        # Serializes an array of objects, wrapping in push_array/pop.
        # Calls +_write_one+ which is generated per-class by the {Compiler}.
        #
        # @param objects [Array<Object>] the objects to serialize
        # @param writer [Oj::StringWriter] the output writer
        # @param key [String, nil] JSON key; nil for root
        # @param filter_mask [FilterMask, nil] nil for unfiltered
        # @param context [SerializationContext, nil] context/scope for method fields
        # @return [void]
        def _serialize_many(objects, writer, key = nil, filter_mask: nil, context: nil)
          writer.push_array(key)
          if filter_mask
            objects.each do |obj|
              writer.push_object
              _write_one(obj, writer, filter_mask, context)
              writer.pop
            end
          else
            objects.each do |obj|
              writer.push_object
              _write_one(obj, writer, nil, context)
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
        # @param writer [Oj::StringWriter] the output writer
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

        # Hash-path variant of +_write_value+. Assigns directly to a Hash.
        # Delegates to +ValuesWriter.write+ via a {ValueCapture} writer so
        # the existing type-coercion pipeline is reused — no explicit
        # +type.deserialize+ needed here.
        #
        # @param attribute [Panko::Attribute] the attribute being written
        # @param value [Object] the raw value
        # @param result [Hash] the output hash
        # @return [void]
        def _write_value_hash(attribute, value, result)
          if value.nil?
            result[attribute.name_for_serialization] = nil
            return
          end

          capture = Panko::CodeGen::ValueCapture.instance
          Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(capture, attribute, value)
          result[attribute.name_for_serialization] = capture.value
        end

        # Hash-path helper for non-direct cached attributes.
        # Passes a {ValueCapture} as the writer so the cached type writer
        # coerces the value, then stores the captured result in the hash.
        #
        # @param aw [ActiveRecordAttributesWriter] the writer with caches
        # @param i [Integer] attribute index
        # @param value [Object] the raw non-nil value
        # @param result [Hash] the output hash
        # @return [void]
        def _write_cached_value_hash(aw, i, value, result)
          capture = Panko::CodeGen::ValueCapture.instance
          unless aw.wtr[i].write(value, capture, aw.key[i])
            Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(capture, aw.attrs[i], value)
          end
          result[aw.key[i]] = capture.value
        end

        # Serializes a single object to a Ruby Hash (no writer).
        #
        # @param object [Object] the object to serialize
        # @param filter_mask [FilterMask, nil] nil for unfiltered
        # @param context [SerializationContext, nil] context/scope for method fields
        # @return [Hash]
        def serialize_one_hash(object:, filter_mask: nil, context: nil)
          _write_one_hash(object, filter_mask, context)
        end

        # Serializes an array of objects to an Array of Hashes (no writer).
        #
        # @param objects [Array<Object>] the objects to serialize
        # @param filter_mask [FilterMask, nil] nil for unfiltered
        # @param context [SerializationContext, nil] context/scope for method fields
        # @return [Array<Hash>]
        def serialize_many_hash(objects:, filter_mask: nil, context: nil)
          objects.map { |obj| _write_one_hash(obj, filter_mask, context) }
        end
      end
    end
  end
end
