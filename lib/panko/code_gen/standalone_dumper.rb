# frozen_string_literal: true

module Panko
  module CodeGen
    # Dumps a serializer's descriptor to a self-contained Ruby file that defines
    # `<Name>Generated` — a class with its own dispatch, cold paths, and helpers.
    #
    # Playground / experimentation only. Not used by the runtime compile path.
    class StandaloneDumper
      MODES = %i[json hash].freeze

      # @param descriptor [Panko::SerializationDescriptor]
      # @param modes [Array<Symbol>] subset of [:json, :hash]
      def initialize(descriptor, modes: MODES)
        validate_modes!(modes)
        raise ArgumentError, "cannot dump anonymous serializer" if descriptor.type.name.nil?

        @descriptor = descriptor
        @modes = modes
        @type = descriptor.type
        @attrs = descriptor.attributes
        @method_fields = descriptor.method_fields
        @has_one_assocs = descriptor.has_one_associations
        @has_many_assocs = descriptor.has_many_associations
      end

      # Returns the full Ruby source for the standalone file.
      # @return [String]
      def to_source
        [
          emit_header,
          emit_class_open,
          emit_entry_points,
          emit_dispatch,
          emit_attribute_writes,
          emit_method_fields,
          emit_has_one,
          emit_has_many,
          emit_stubs,
          emit_hash_object_writes,
          emit_cold_paths,
          emit_helpers,
          emit_class_close_and_bootstrap
        ].reject(&:empty?).join("\n\n")
      end

      # Writes the source to +file+.
      # @param file [String]
      # @return [void]
      def dump(file)
        File.write(file, to_source)
      end

      private

      def emit_header
        <<~HEADER
          # frozen_string_literal: true
          # Panko standalone generated dump for #{@type.name} (modes: #{@modes.inspect})
          # Defines #{generated_name} — a self-contained serializer class with its own
          # dispatch. Not coupled to Panko::CodeGen::GeneratedBase at call time.
        HEADER
      end

      def emit_class_open
        <<~RUBY
          class #{generated_name}
            class << self
              attr_accessor :_attrs, :_ar_writer, :_serializer,
                            :_has_one_assocs, :_has_many_assocs,
                            :_ho_static_masks, :_hm_static_masks
        RUBY
      end

      def emit_class_close_and_bootstrap
        parts = []
        parts << "  end"  # close class << self
        parts << ""
        parts << "  desc = #{@type.name}._descriptor"
        parts << "  @_attrs = desc.attributes"
        parts << "  @_ar_writer = Panko::CodeGen::ActiveRecordAttributesWriter.new(attrs: @_attrs, klass: self)"

        unless @method_fields.empty?
          parts << "  ser = #{@type.name}.new(_skip_init: true)"
          parts << "  ser.serialization_context = desc.serializer&.serialization_context"
          parts << "  @_serializer = ser"
        end

        parts << "  @_has_one_assocs = desc.has_one_associations"
        parts << "  @_has_many_assocs = desc.has_many_associations"
        parts << "  @_ho_static_masks = desc.has_one_associations.map do |assoc|"
        parts << "    sub = assoc.descriptor.type._descriptor"
        parts << "    Panko::SerializationDescriptor.compute_filter_mask(assoc.descriptor, sub) || Panko::CodeGen::FilterMask::EMPTY"
        parts << "  end"
        parts << "  @_hm_static_masks = desc.has_many_associations.map do |assoc|"
        parts << "    sub = assoc.descriptor.type._descriptor"
        parts << "    Panko::SerializationDescriptor.compute_filter_mask(assoc.descriptor, sub) || Panko::CodeGen::FilterMask::EMPTY"
        parts << "  end"
        parts << "end"

        parts.join("\n")
      end

      # Indents every non-blank line with 4 spaces (inside `class << self`).
      # @param block [String]
      # @return [String]
      def indent4(block)
        block.each_line.map { |l| l.strip.empty? ? "" : "    #{l.rstrip}" }.join("\n")
      end

      def emit_entry_points
        parts = []
        if json_mode?
          parts << indent4(<<~RUBY)
            def serialize_one(object:, writer:, key: nil, filter_mask: nil, context: nil)
              _serialize_one(object, writer, key, filter_mask || Panko::CodeGen::FilterMask::EMPTY, context)
            end

            def serialize_many(objects:, writer:, key: nil, filter_mask: nil, context: nil)
              _serialize_many(objects, writer, key, filter_mask || Panko::CodeGen::FilterMask::EMPTY, context)
            end
          RUBY
        end

        if hash_mode?
          parts << indent4(<<~RUBY)
            def serialize_one_hash(object:, filter_mask: nil, context: nil)
              _write_one_hash(object, filter_mask || Panko::CodeGen::FilterMask::EMPTY, context)
            end

            def serialize_many_hash(objects:, filter_mask: nil, context: nil)
              fm = filter_mask || Panko::CodeGen::FilterMask::EMPTY
              objects.map { |obj| _write_one_hash(obj, fm, context) }
            end
          RUBY
        end

        parts.join("\n\n")
      end

      def emit_dispatch
        parts = []
        if json_mode?
          parts << indent4(<<~RUBY)
            def _serialize_one(object, writer, key, filter_mask, context)
              writer.push_object(key)
              _write_one(object, writer, filter_mask, context)
              writer.pop
            end

            def _serialize_many(objects, writer, key, filter_mask, context)
              writer.push_array(key)
              objects.each do |obj|
                writer.push_object
                _write_one(obj, writer, filter_mask, context)
                writer.pop
              end
              writer.pop
            end

            def _write_one(object, writer, filter_mask, context)
              if object.is_a?(ActiveRecord::Base)
                @_ar_writer.write(object, writer, filter_mask)
              elsif object.is_a?(Hash)
                _write_hash(object, writer, filter_mask.attrs)
              else
                _write_plain(object, writer, filter_mask.attrs)
              end
              _write_method_fields(object, writer, filter_mask.method_fields, context)
              _write_has_one(object, writer, filter_mask, context)
              _write_has_many(object, writer, filter_mask, context)
            end
          RUBY
        end

        if hash_mode?
          parts << indent4(<<~RUBY)
            def _write_one_hash(object, filter_mask, context)
              result = {}
              if object.is_a?(ActiveRecord::Base)
                @_ar_writer.write_hash(object, result, filter_mask)
              elsif object.is_a?(Hash)
                _write_hash_hash(object, result, filter_mask.attrs)
              else
                _write_plain_hash(object, result, filter_mask.attrs)
              end
              _write_method_fields_hash(object, result, filter_mask.method_fields, context)
              _write_has_one_hash(object, result, filter_mask, context)
              _write_has_many_hash(object, result, filter_mask, context)
              result
            end
          RUBY
        end

        parts.join("\n\n")
      end

      def emit_attribute_writes
        parts = []

        if json_mode?
          e = Emitter.new
          e << "def _write_plain(object, writer, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_plain_attr(i, attr.name_sym, attr.name_for_serialization) }
          e << "end"
          parts << indent4(e.to_source)

          e = Emitter.new
          e << "def _write_indexed_cached(row, writer, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_cached_attr(i, attr.name_for_serialization) }
          e << "end"
          parts << indent4(e.to_source)
        end

        if hash_mode?
          e = Emitter.new
          e << "def _write_plain_hash(object, result, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_plain_attr_hash(i, attr.name_sym, attr.name_for_serialization) }
          e << "end"
          parts << indent4(e.to_source)

          e = Emitter.new
          e << "def _write_indexed_cached_hash(row, result, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_cached_attr_hash(i, attr.name_for_serialization) }
          e << "end"
          parts << indent4(e.to_source)
        end

        parts.join("\n\n")
      end

      def emit_method_fields
        return "" if @method_fields.empty?

        parts = []
        if json_mode?
          e = Emitter.new
          e << "def _write_method_fields(object, writer, mf_mask, context)"
          e << "ser = @_serializer"
          e << "ser.serialization_context = context"
          e << "ser.instance_variable_set(:@object, object)"
          @method_fields.each_with_index { |mf, i| e.emit_method_field(i, mf.name_sym, mf.name_for_serialization) }
          e << "end"
          parts << indent4(e.to_source)
        end

        if hash_mode?
          e = Emitter.new
          e << "def _write_method_fields_hash(object, result, mf_mask, context)"
          e << "ser = @_serializer"
          e << "ser.serialization_context = context"
          e << "ser.instance_variable_set(:@object, object)"
          @method_fields.each_with_index { |mf, i| e.emit_method_field_hash(i, mf.name_sym, mf.name_for_serialization) }
          e << "end"
          parts << indent4(e.to_source)
        end

        parts.join("\n\n")
      end

      def emit_has_one_target_resolution(lines, name_sym, indent:)
        lines << "#{indent}if object.is_a?(ActiveRecord::Base) && object.class.reflect_on_association(:#{name_sym})"
        lines << "#{indent}  _ar_assoc = object.association(:#{name_sym})"
        lines << "#{indent}  target = _ar_assoc.loaded? ? _ar_assoc.target : object.#{name_sym}"
        lines << "#{indent}else"
        lines << "#{indent}  target = object.#{name_sym}"
        lines << "#{indent}end"
      end

      def emit_has_one
        return "" if @has_one_assocs.empty?

        parts = []

        if json_mode?
          lines = []
          lines << "def _write_has_one(object, writer, filter_mask, context)"
          lines << "  ho_mask = filter_mask.has_one"
          lines << "  ho_masks = filter_mask.has_one_masks"
          @has_one_assocs.each_with_index do |assoc, i|
            sub_name = generated_name(assoc.descriptor.type)
            lines << "  if ho_mask[#{i}]"
            emit_has_one_target_resolution(lines, assoc.name_sym, indent: "    ")
            lines << "    if target.nil?"
            lines << "      writer.push_value(nil, #{assoc.name_str.inspect})"
            lines << "    else"
            lines << "      nested = ho_masks[#{i}] || @_ho_static_masks[#{i}]"
            lines << "      writer.push_object(#{assoc.name_str.inspect})"
            lines << "      #{sub_name}._write_one(target, writer, nested, context)"
            lines << "      writer.pop"
            lines << "    end"
            lines << "  end"
          end
          lines << "end"
          parts << indent4(lines.join("\n"))
        end

        if hash_mode?
          lines = []
          lines << "def _write_has_one_hash(object, result, filter_mask, context)"
          lines << "  ho_mask = filter_mask.has_one"
          lines << "  ho_masks = filter_mask.has_one_masks"
          @has_one_assocs.each_with_index do |assoc, i|
            sub_name = generated_name(assoc.descriptor.type)
            lines << "  if ho_mask[#{i}]"
            emit_has_one_target_resolution(lines, assoc.name_sym, indent: "    ")
            lines << "    if target.nil?"
            lines << "      result[#{assoc.name_str.inspect}] = nil"
            lines << "    else"
            lines << "      nested = ho_masks[#{i}] || @_ho_static_masks[#{i}]"
            lines << "      result[#{assoc.name_str.inspect}] = #{sub_name}._write_one_hash(target, nested, context)"
            lines << "    end"
            lines << "  end"
          end
          lines << "end"
          parts << indent4(lines.join("\n"))
        end

        parts.join("\n\n")
      end

      def emit_has_many
        return "" if @has_many_assocs.empty?

        parts = []

        if json_mode?
          lines = []
          lines << "def _write_has_many(object, writer, filter_mask, context)"
          lines << "  hm_mask = filter_mask.has_many"
          lines << "  hm_masks = filter_mask.has_many_masks"
          @has_many_assocs.each_with_index do |assoc, i|
            sub_name = generated_name(assoc.descriptor.type)
            lines << "  if hm_mask[#{i}]"
            lines << "    collection = object.#{assoc.name_sym}"
            lines << "    if collection.nil?"
            lines << "      writer.push_value(nil, #{assoc.name_str.inspect})"
            lines << "    else"
            lines << "      _mask = hm_masks[#{i}] || @_hm_static_masks[#{i}]"
            lines << "      writer.push_array(#{assoc.name_str.inspect})"
            lines << "      collection.each do |_el|"
            lines << "        writer.push_object"
            lines << "        #{sub_name}._write_one(_el, writer, _mask, context)"
            lines << "        writer.pop"
            lines << "      end"
            lines << "      writer.pop"
            lines << "    end"
            lines << "  end"
          end
          lines << "end"
          parts << indent4(lines.join("\n"))
        end

        if hash_mode?
          lines = []
          lines << "def _write_has_many_hash(object, result, filter_mask, context)"
          lines << "  hm_mask = filter_mask.has_many"
          lines << "  hm_masks = filter_mask.has_many_masks"
          @has_many_assocs.each_with_index do |assoc, i|
            sub_name = generated_name(assoc.descriptor.type)
            lines << "  if hm_mask[#{i}]"
            lines << "    collection = object.#{assoc.name_sym}"
            lines << "    if collection.nil?"
            lines << "      result[#{assoc.name_str.inspect}] = nil"
            lines << "    else"
            lines << "      _mask = hm_masks[#{i}] || @_hm_static_masks[#{i}]"
            lines << "      result[#{assoc.name_str.inspect}] = collection.map { |_el| #{sub_name}._write_one_hash(_el, _mask, context) }"
            lines << "    end"
            lines << "  end"
          end
          lines << "end"
          parts << indent4(lines.join("\n"))
        end

        parts.join("\n\n")
      end

      def emit_hash_object_writes
        parts = []

        if json_mode?
          parts << indent4(<<~RUBY)
            def _write_hash(object, writer, attr_mask)
              @_attrs.each_with_index do |attr, i|
                next unless attr_mask[i]

                writer.push_value(object[attr.name], attr.name_for_serialization)
              end
            end
          RUBY
        end

        if hash_mode?
          parts << indent4(<<~RUBY)
            def _write_hash_hash(object, result, attr_mask)
              @_attrs.each_with_index do |attr, i|
                next unless attr_mask[i]

                result[attr.name_for_serialization] = object[attr.name].as_json
              end
            end
          RUBY
        end

        parts.join("\n\n")
      end

      def emit_cold_paths
        parts = []

        if json_mode?
          parts << indent4(<<~RUBY)
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
          RUBY
        end

        if hash_mode?
          parts << indent4(<<~RUBY)
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
          RUBY
        end

        parts.join("\n\n")
      end

      def emit_helpers
        parts = []

        parts << indent4(<<~RUBY)
          def _resolve_type(attribute, rs)
            attribute.type = rs.additional_types[attribute.name] if rs.try_additional
            attribute.type ||= rs.types[attribute.name]
          end
        RUBY

        if json_mode?
          parts << indent4(<<~RUBY)
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
          RUBY
        end

        if hash_mode?
          parts << indent4(<<~RUBY)
            def _write_value_hash(attribute, value, result)
              if value.nil?
                result[attribute.name_for_serialization] = nil
                return
              end

              capture = Panko::CodeGen::ValueCapture.instance
              Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(capture, attribute, value)
              result[attribute.name_for_serialization] = capture.value
            end

            def _write_cached_value_hash(wtr, attr, key, value, result)
              capture = Panko::CodeGen::ValueCapture.instance
              unless wtr.write(value, capture, key)
                Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(capture, attr, value)
              end
              result[key] = capture.value
            end
          RUBY
        end

        parts.join("\n\n")
      end

      def emit_stubs
        stubs = []

        if @method_fields.empty?
          stubs << "def _write_method_fields(*); end" if json_mode?
          stubs << "def _write_method_fields_hash(*); end" if hash_mode?
        end

        if @has_one_assocs.empty?
          stubs << "def _write_has_one(*); end" if json_mode?
          stubs << "def _write_has_one_hash(*); end" if hash_mode?
        end

        if @has_many_assocs.empty?
          stubs << "def _write_has_many(*); end" if json_mode?
          stubs << "def _write_has_many_hash(*); end" if hash_mode?
        end

        stubs.empty? ? "" : indent4(stubs.join("\n"))
      end

      def validate_modes!(modes)
        raise ArgumentError, ":modes must be a non-empty array" if modes.nil? || modes.empty?

        unknown = modes - MODES
        raise ArgumentError, "unknown modes: #{unknown.inspect}, expected subset of #{MODES.inspect}" unless unknown.empty?
      end

      def json_mode?
        @modes.include?(:json)
      end

      def hash_mode?
        @modes.include?(:hash)
      end

      def generated_name(type = @type)
        "#{type.name}Generated"
      end
    end
  end
end
