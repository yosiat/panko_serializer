# frozen_string_literal: true

module Panko
  module CodeGen
    # Abstract base class for all generated serializer classes.
    #
    # The {Compiler} defines per-serializer +_write_one+, +_write_one_hash+
    # and attribute writers on each subclass via +module_eval+. This base
    # class hosts only the public entry points, the generic +_serialize_many+
    # batch loop, and the cold-path / value-helper methods.
    #
    # All methods receive a {FilterMask} (never nil — {FilterMask::EMPTY}
    # for unfiltered calls) so each concern needs only one method.
    #
    # Runtime state is held by a single delegate:
    # - +@_ar_writer+ — {ActiveRecordAttributesWriter}, owns parallel caches
    class GeneratedBase
      class << self
        # Set by the Compiler during class generation.

        # @return [ActiveRecordAttributesWriter]
        # @!attribute [w] _ar_writer
        attr_writer :_ar_writer

        # @return [Array<Panko::Attribute>]
        # @!attribute [w] _attrs
        attr_writer :_attrs

        # Anonymous subclass of the user's serializer class. Its initializer
        # sets +@serialization_context+ and +@object+ directly, so each
        # +_write_one+ call constructs a fresh instance for method-field
        # dispatch. Set by the Compiler only when the serializer declares
        # method fields.
        # @return [Class<Panko::Serializer>]
        # @!attribute [w] _serializer_class
        attr_writer :_serializer_class

        # @return [Array<Panko::Association>]
        # @!attribute [w] _has_one_assocs
        attr_writer :_has_one_assocs

        # @return [Array<Panko::Association>]
        # @!attribute [w] _has_many_assocs
        attr_writer :_has_many_assocs

        # Per-association static sub-masks for has_one.
        # Always a FilterMask per slot ({FilterMask::EMPTY} when the
        # association has no static filter) — never nil.
        # @return [Array<FilterMask>]
        # @!attribute [w] _ho_static_masks
        attr_writer :_ho_static_masks

        # Per-association static sub-masks for has_many.
        # Always a FilterMask per slot ({FilterMask::EMPTY} when the
        # association has no static filter) — never nil.
        # @return [Array<FilterMask>]
        # @!attribute [w] _hm_static_masks
        attr_writer :_hm_static_masks

        # --- Public entry points ---

        # Serializes a single object to the given writer.
        #
        # @param object [Object] the object to serialize
        # @param writer [Oj::StringWriter] the output writer
        # @param key [String, nil] JSON key for the object; nil for root
        # @param filter_mask [FilterMask, nil] nil converted to FilterMask::EMPTY
        # @param context [SerializationContext, nil] context/scope for method fields
        # @return [void]
        def serialize_one(object:, writer:, key: nil, filter_mask: nil, context: nil)
          _write_one(object, writer, key, filter_mask || FilterMask::EMPTY, context)
        end

        # Serializes an array of objects to the given writer.
        #
        # @param objects [Array<Object>] the objects to serialize
        # @param writer [Oj::StringWriter] the output writer
        # @param key [String, nil] JSON key for the array; nil for root
        # @param filter_mask [FilterMask, nil] nil converted to FilterMask::EMPTY
        # @param context [SerializationContext, nil] context/scope for method fields
        # @return [void]
        def serialize_many(objects:, writer:, key: nil, filter_mask: nil, context: nil)
          _serialize_many(objects, writer, key, filter_mask || FilterMask::EMPTY, context)
        end

        # Serializes a single object to a Ruby Hash.
        #
        # @param object [Object] the object to serialize
        # @param filter_mask [FilterMask, nil] nil converted to FilterMask::EMPTY
        # @param context [SerializationContext, nil] context/scope
        # @return [Hash]
        def serialize_one_hash(object:, filter_mask: nil, context: nil)
          _write_one_hash(object, filter_mask || FilterMask::EMPTY, context)
        end

        # Serializes an array of objects to an Array of Hashes.
        #
        # @param objects [Array<Object>] the objects to serialize
        # @param filter_mask [FilterMask, nil] nil converted to FilterMask::EMPTY
        # @param context [SerializationContext, nil] context/scope
        # @return [Array<Hash>]
        def serialize_many_hash(objects:, filter_mask: nil, context: nil)
          fm = filter_mask || FilterMask::EMPTY
          objects.map { |obj| _write_one_hash(obj, fm, context) }
        end

        # --- Generic batch dispatch ---

        # Serializes an array of objects to the writer as a JSON array.
        # Each element is delegated to the per-serializer +_write_one+, which
        # owns its own push_object / pop.
        #
        # @param objects [Array<Object>] the objects to serialize
        # @param writer [Oj::StringWriter] the output writer
        # @param key [String, nil] JSON key for the array
        # @param filter_mask [FilterMask] never nil
        # @param context [SerializationContext, nil] context/scope
        # @return [void]
        def _serialize_many(objects, writer, key, filter_mask, context)
          writer.push_array(key)
          objects.each { |obj| _write_one(obj, writer, nil, filter_mask, context) }
          writer.pop
        end

        # --- Cold-path AR methods (loops, run once or rarely) ---

        # First-pass: resolves types for all attributes, writes values for
        # included ones. Runs once per record class, then {build_caches!}
        # fills the parallel arrays for the cached hot path.
        #
        # @param aw [ActiveRecordAttributesWriter] the writer with attrs array
        # @param rs [RecordState] record state with column_indexes and row
        # @param writer [Oj::StringWriter] the output writer
        # @param attr_mask [Array<Boolean>, INCLUDE_ALL] per-attribute mask
        # @return [void]
        def _write_indexed_first_pass(aw, rs, writer, attr_mask)
          ci = rs.column_indexes
          row = rs.row
          aw.attrs.each_with_index do |attr, i|
            ci_val = ci[attr.name]
            v = ci_val ? row[ci_val] : nil
            _resolve_type(attr, rs) if attr.type.nil? && v
            _write_value(attr, v, writer) if attr_mask[i]
          end
        end

        # Hash-path variant of {_write_indexed_first_pass}.
        def _write_indexed_first_pass_hash(aw, rs, result, attr_mask)
          ci = rs.column_indexes
          row = rs.row
          aw.attrs.each_with_index do |attr, i|
            ci_val = ci[attr.name]
            v = ci_val ? row[ci_val] : nil
            _resolve_type(attr, rs) if attr.type.nil? && v
            _write_value_hash(attr, v, result) if attr_mask[i]
          end
        end

        # Fallback for dirty/non-indexed AR records. Checks the attributes
        # hash first (dirty values), falls back to indexed row, then to
        # RecordState read for non-indexed records.
        #
        # @param aw [ActiveRecordAttributesWriter] the writer with attrs array
        # @param rs [RecordState] record state
        # @param writer [Oj::StringWriter] the output writer
        # @param attr_mask [Array<Boolean>, INCLUDE_ALL] per-attribute mask
        # @return [void]
        def _write_ar_fallback(aw, rs, writer, attr_mask)
          attrs = aw.attrs
          if rs.is_indexed_row
            ci = rs.column_indexes
            row = rs.row
            ah = rs.attributes_hash
            attrs.each_with_index do |attr, i|
              next unless attr_mask[i]

              v = nil
              am = ah[attr.name]
              if am
                v = am.instance_variable_get(:@value_before_type_cast)
                attr.type ||= am.instance_variable_get(:@type)
              end
              if v.nil?
                ci_val = ci[attr.name]
                v = row[ci_val] if ci_val
              end
              _resolve_type(attr, rs) if attr.type.nil? && v
              _write_value(attr, v, writer)
            end
          else
            attrs.each_with_index do |attr, i|
              next unless attr_mask[i]

              v = rs.read_attribute(attr)
              Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attr, v)
            end
          end
        end

        # Hash-path variant of {_write_ar_fallback}.
        def _write_ar_fallback_hash(aw, rs, result, attr_mask)
          attrs = aw.attrs
          if rs.is_indexed_row
            ci = rs.column_indexes
            row = rs.row
            ah = rs.attributes_hash
            attrs.each_with_index do |attr, i|
              next unless attr_mask[i]

              v = nil
              am = ah[attr.name]
              if am
                v = am.instance_variable_get(:@value_before_type_cast)
                attr.type ||= am.instance_variable_get(:@type)
              end
              if v.nil?
                ci_val = ci[attr.name]
                v = row[ci_val] if ci_val
              end
              _resolve_type(attr, rs) if attr.type.nil? && v
              _write_value_hash(attr, v, result)
            end
          else
            attrs.each_with_index do |attr, i|
              next unless attr_mask[i]

              v = rs.read_attribute(attr)
              _write_value_hash(attr, v, result)
            end
          end
        end

        # --- Type resolution and value writing helpers ---

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

        # Hash-path variant of +_write_value+. Delegates to +ValuesWriter.write+
        # via a {ValueCapture} writer so the existing type-coercion pipeline is
        # reused.
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
        # @param wtr [Object] the cached ValuesWriter for this attribute
        # @param attr [Panko::Attribute] the attribute (for fallback)
        # @param key [String] the serialization key
        # @param value [Object] the raw non-nil value
        # @param result [Hash] the output hash
        # @return [void]
        def _write_cached_value_hash(wtr, attr, key, value, result)
          capture = Panko::CodeGen::ValueCapture.instance
          unless wtr.write(value, capture, key)
            Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(capture, attr, value)
          end
          result[key] = capture.value
        end

        # --- Source dump API ---

        # Records a generated source snippet for later retrieval via {#dump_source}.
        #
        # @param label [String] method label (e.g. "_write_indexed_cached")
        # @param source [String] the generated Ruby source
        # @return [void]
        def _record_source(label, source)
          @_generated_sources ||= {}
          @_generated_sources[label] = source
        end

        # Returns all generated method sources as a formatted string.
        # Each method is preceded by a comment with its label.
        #
        # @return [String]
        def dump_source
          return "" unless defined?(@_generated_sources) && @_generated_sources

          @_generated_sources.map { |label, src| "# #{label}\n#{src}" }.join("\n\n")
        end
      end
    end
  end
end
