# frozen_string_literal: true

# Panko standalone generated dump for PlayerPanko (modes: [:json])
# Defines PlayerPankoGenerated — a self-contained serializer class with its own
# dispatch. Not coupled to Panko::CodeGen::GeneratedBase at call time.

class PlayerPankoGenerated
  class << self
    attr_accessor :_attrs, :_ar_writer, :_serializer,
      :_has_one_assocs, :_has_many_assocs,
      :_ho_static_masks, :_hm_static_masks

    def serialize_one(object:, writer:, key: nil, filter_mask: nil, context: nil)
      _write_one(object, writer, key, filter_mask || Panko::CodeGen::FilterMask::EMPTY, context)
    end

    def serialize_many(objects:, writer:, key: nil, filter_mask: nil, context: nil)
      _serialize_many(objects, writer, key, filter_mask || Panko::CodeGen::FilterMask::EMPTY, context)
    end

    def _write_one(object, writer, key, filter_mask, context)
      writer.push_object(key)
      is_ar = object.is_a?(ActiveRecord::Base)
      if is_ar
        @_ar_writer.write(object, writer, filter_mask)
      elsif object.is_a?(Hash)
        _write_hash(object, writer, filter_mask.attrs)
      else
        _write_plain(object, writer, filter_mask.attrs)
      end
      mf_mask = filter_mask.method_fields
      ser = @_serializer
      ser.serialization_context = context
      ser.instance_variable_set(:@object, object)
      if mf_mask[0]
        mf_result = ser.id
        writer.push_value(mf_result, "id") unless mf_result.equal?(Panko::Engine::SKIP)
      end
      if mf_mask[1]
        mf_result = ser.full_name
        writer.push_value(mf_result, "full_name") unless mf_result.equal?(Panko::Engine::SKIP)
      end
      writer.pop
    end

    def _serialize_many(objects, writer, key, filter_mask, context)
      writer.push_array(key)
      objects.each { |obj| _write_one(obj, writer, nil, filter_mask, context) }
      writer.pop
    end

    def _write_plain(object, writer, attr_mask)
      if attr_mask[0]
        writer.push_value(object.first_name, "first_name")
      end
      if attr_mask[1]
        writer.push_value(object.last_name, "last_name")
      end
    end

    def _write_indexed_cached(row, writer, attr_mask)
      if attr_mask[0]
        v = row[@_col_0]
        if @_dir_0
          writer.push_value(v, "first_name")
        elsif v.nil?
          writer.push_value(nil, "first_name")
        else
          @_wtr_0.write(v, writer, "first_name")
        end
      end
      if attr_mask[1]
        v = row[@_col_1]
        if @_dir_1
          writer.push_value(v, "last_name")
        elsif v.nil?
          writer.push_value(nil, "last_name")
        else
          @_wtr_1.write(v, writer, "last_name")
        end
      end
    end

    def _write_hash(object, writer, attr_mask)
      if attr_mask[0]
        writer.push_value(object["first_name"], "first_name")
      end
      if attr_mask[1]
        writer.push_value(object["last_name"], "last_name")
      end
    end

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

    def _resolve_type(attribute, rs)
      attribute.type = rs.additional_types[attribute.name] if rs.try_additional
      attribute.type ||= rs.types[attribute.name]
    end

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

  desc = PlayerPanko._descriptor
  @_attrs = desc.attributes
  @_ar_writer = Panko::CodeGen::ActiveRecordAttributesWriter.new(attrs: @_attrs, klass: self)
  ser = PlayerPanko.new(_skip_init: true)
  ser.serialization_context = desc.serializer&.serialization_context
  @_serializer = ser
  @_has_one_assocs = desc.has_one_associations
  @_has_many_assocs = desc.has_many_associations
  @_ho_static_masks = desc.has_one_associations.map do |assoc|
    sub = assoc.descriptor.type._descriptor
    Panko::SerializationDescriptor.compute_filter_mask(assoc.descriptor, sub) || Panko::CodeGen::FilterMask::EMPTY
  end
  @_hm_static_masks = desc.has_many_associations.map do |assoc|
    sub = assoc.descriptor.type._descriptor
    Panko::SerializationDescriptor.compute_filter_mask(assoc.descriptor, sub) || Panko::CodeGen::FilterMask::EMPTY
  end
end
