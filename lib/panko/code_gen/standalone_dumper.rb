# frozen_string_literal: true

module Panko
  module CodeGen
    # Dumps a serializer's descriptor to a self-contained Ruby file that defines
    # `<Name>Generated` — a class with its own dispatch, cold paths, and helpers.
    #
    # The generated source mirrors what the runtime +Compiler+ produces for the
    # same descriptor: a per-serializer +_write_one+ / +_write_one_hash+ that
    # owns +push_object/pop+ on the JSON path, checks +object.is_a?(AR::Base)+
    # once into +is_ar+, and inlines method-field / has_one / has_many blocks
    # (emitting nothing when those concerns are absent).
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
              attr_accessor :_attrs, :_ar_writer, :_serializer_class,
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
        # Stamp per-attribute ivars in a stable order — +@_attr_i+ first,
        # then +@_attr_i_key+ for the E6 unrolled fallback direct-dispatch
        # path. Mirrors +ActiveRecordAttributesWriter#stamp_attr_ivars!+ for
        # the runtime compile.
        @attrs.each_with_index { |_attr, i| parts << "  @_attr_#{i} = @_attrs[#{i}]" }
        @attrs.each_with_index { |_attr, i| parts << "  @_attr_#{i}_key = @_attr_#{i}.name_for_serialization" }
        parts << "  @_ar_writer = Panko::CodeGen::ActiveRecordAttributesWriter.new(attrs: @_attrs, klass: self)"

        unless @method_fields.empty?
          parts << "  @_serializer_class = Class.new(#{@type.name}) do"
          parts << "    def initialize(serialization_context, object)"
          parts << "      @serialization_context = serialization_context"
          parts << "      @object = object"
          parts << "    end"
          parts << "  end"
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
      def indent4(block)
        block.each_line.map { |l| l.strip.empty? ? "" : "    #{l.rstrip}" }.join("\n")
      end

      def emit_entry_points
        parts = []
        if json_mode?
          parts << indent4(<<~RUBY)
            def serialize_one(object:, writer:, key: nil, filter_mask: nil, context: nil)
              _write_one(object, writer, key, filter_mask || Panko::CodeGen::FilterMask::EMPTY, context)
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
        parts << indent4(build_write_one) if json_mode?

        if json_mode?
          parts << indent4(<<~RUBY)
            def _serialize_many(objects, writer, key, filter_mask, context)
              writer.push_array(key)
              objects.each { |obj| _write_one(obj, writer, nil, filter_mask, context) }
              writer.pop
            end
          RUBY
        end

        parts << indent4(build_write_one_hash) if hash_mode?

        parts.join("\n\n")
      end

      # Inlined _write_one for the JSON path.
      def build_write_one
        lines = []
        lines << "def _write_one(object, writer, key, filter_mask, context)"
        lines << "  writer.push_object(key)"
        lines << "  is_ar = object.is_a?(ActiveRecord::Base)"
        lines << "  if is_ar"
        lines << "    @_ar_writer.write(object, writer, filter_mask)"
        lines << "  elsif object.is_a?(Hash)"
        lines << "    _write_hash(object, writer, filter_mask.attrs)"
        lines << "  else"
        lines << "    _write_plain(object, writer, filter_mask.attrs)"
        lines << "  end"
        append_method_fields_block(lines, hash: false) unless @method_fields.empty?
        append_has_one_block(lines, hash: false) unless @has_one_assocs.empty?
        append_has_many_block(lines, hash: false) unless @has_many_assocs.empty?
        lines << "  writer.pop"
        lines << "end"
        lines.join("\n")
      end

      # Inlined _write_one_hash for the Hash path.
      def build_write_one_hash
        lines = []
        lines << "def _write_one_hash(object, filter_mask, context)"
        lines << "  result = {}"
        lines << "  is_ar = object.is_a?(ActiveRecord::Base)"
        lines << "  if is_ar"
        lines << "    @_ar_writer.write_hash(object, result, filter_mask)"
        lines << "  elsif object.is_a?(Hash)"
        lines << "    _write_hash_hash(object, result, filter_mask.attrs)"
        lines << "  else"
        lines << "    _write_plain_hash(object, result, filter_mask.attrs)"
        lines << "  end"
        append_method_fields_block(lines, hash: true) unless @method_fields.empty?
        append_has_one_block(lines, hash: true) unless @has_one_assocs.empty?
        append_has_many_block(lines, hash: true) unless @has_many_assocs.empty?
        lines << "  result"
        lines << "end"
        lines.join("\n")
      end

      def append_method_fields_block(lines, hash:)
        lines << "  mf_mask = filter_mask.method_fields"
        lines << "  ser = @_serializer_class.new(context, object)"
        @method_fields.each_with_index do |mf, i|
          lines << "  if mf_mask[#{i}]"
          if hash
            lines << "    v = ser.#{mf.name_sym}"
            lines << "    result[#{mf.name_for_serialization.inspect}] = v.as_json unless v.equal?(Panko::Engine::SKIP)"
          else
            lines << "    mf_result = ser.#{mf.name_sym}"
            lines << "    writer.push_value(mf_result, #{mf.name_for_serialization.inspect}) unless mf_result.equal?(Panko::Engine::SKIP)"
          end
          lines << "  end"
        end
      end

      def append_has_one_block(lines, hash:)
        lines << "  ho_mask = filter_mask.has_one"
        lines << "  ho_masks = filter_mask.has_one_masks"
        @has_one_assocs.each_with_index do |assoc, i|
          sub_name = generated_name(assoc.descriptor.type)
          key_str = assoc.name_str.inspect
          lines << "  if ho_mask[#{i}]"
          emit_has_one_target_resolution(lines, assoc.name_sym, indent: "    ")
          lines << "    if target.nil?"
          lines << (hash ? "      result[#{key_str}] = nil" : "      writer.push_value(nil, #{key_str})")
          lines << "    else"
          lines << "      nested = ho_masks[#{i}] || @_ho_static_masks[#{i}]"
          lines << (hash ? "      result[#{key_str}] = #{sub_name}._write_one_hash(target, nested, context)" : "      #{sub_name}._write_one(target, writer, #{key_str}, nested, context)")
          lines << "    end"
          lines << "  end"
        end
      end

      def append_has_many_block(lines, hash:)
        lines << "  hm_mask = filter_mask.has_many"
        lines << "  hm_masks = filter_mask.has_many_masks"
        @has_many_assocs.each_with_index do |assoc, i|
          sub_name = generated_name(assoc.descriptor.type)
          key_str = assoc.name_str.inspect
          lines << "  if hm_mask[#{i}]"
          lines << "    collection = object.#{assoc.name_sym}"
          lines << "    if collection.nil?"
          lines << (hash ? "      result[#{key_str}] = nil" : "      writer.push_value(nil, #{key_str})")
          lines << "    else"
          lines << "      _mask = hm_masks[#{i}] || @_hm_static_masks[#{i}]"
          if hash
            lines << "      result[#{key_str}] = collection.map { |_el| #{sub_name}._write_one_hash(_el, _mask, context) }"
          else
            lines << "      writer.push_array(#{key_str})"
            lines << "      collection.each { |_el| #{sub_name}._write_one(_el, writer, nil, _mask, context) }"
            lines << "      writer.pop"
          end
          lines << "    end"
          lines << "  end"
        end
      end

      # Has_one target resolution. Reuses the +is_ar+ local set up at the top
      # of +_write_one+ so +is_a?(ActiveRecord::Base)+ is not re-checked.
      def emit_has_one_target_resolution(lines, name_sym, indent:)
        lines << "#{indent}if is_ar && object.class.reflect_on_association(:#{name_sym})"
        lines << "#{indent}  _ar_assoc = object.association(:#{name_sym})"
        lines << "#{indent}  target = _ar_assoc.loaded? ? _ar_assoc.target : object.#{name_sym}"
        lines << "#{indent}else"
        lines << "#{indent}  target = object.#{name_sym}"
        lines << "#{indent}end"
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

      def emit_hash_object_writes
        parts = []

        if json_mode?
          e = Emitter.new
          e << "def _write_hash(object, writer, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_hash_attr(i, attr.name, attr.name_for_serialization) }
          e << "end"
          parts << indent4(e.to_source)
        end

        if hash_mode?
          e = Emitter.new
          e << "def _write_hash_hash(object, result, attr_mask)"
          @attrs.each_with_index { |attr, i| e.emit_hash_attr_hash(i, attr.name, attr.name_for_serialization) }
          e << "end"
          parts << indent4(e.to_source)
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
          RUBY
          parts << indent4(build_write_ar_fallback)
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
          RUBY
          parts << indent4(build_write_ar_fallback_hash)
        end

        parts.join("\n\n")
      end

      # Builds +_write_ar_fallback+ using the same emitter the runtime
      # Compiler uses so the dumped source matches what gets compiled.
      # The non-indexed +else+ branch is the E5/E6 unrolled direct-dispatch
      # variant (see +Emitter::ActiveRecordAttributes#emit_fallback_attr+).
      def build_write_ar_fallback
        e = Emitter.new
        e << "def _write_ar_fallback(aw, rs, writer, attr_mask)"
        e << "  attrs = aw.attrs"
        e << "  if rs.is_indexed_row"
        e << "    ci = rs.column_indexes"
        e << "    row = rs.row"
        e << "    ah = rs.attributes_hash"
        e << "    attrs.each_with_index do |attr, i|"
        e << "      next unless attr_mask[i]"
        e << ""
        e << "      v = nil"
        e << "      am = ah[attr.name]"
        e << "      if am"
        e << "        v = am.instance_variable_get(:@value_before_type_cast)"
        e << "        attr.type ||= am.instance_variable_get(:@type)"
        e << "      end"
        e << "      if v.nil?"
        e << "        ci_val = ci[attr.name]"
        e << "        v = row[ci_val] if ci_val"
        e << "      end"
        e << "      _resolve_type(attr, rs) if attr.type.nil? && v"
        e << "      _write_value(attr, v, writer)"
        e << "    end"
        e << "  else"
        @attrs.each_with_index { |_attr, i| e.emit_fallback_attr(i) }
        e << "  end"
        e << "end"
        e.to_source
      end

      # Hash-path twin of +build_write_ar_fallback+.
      def build_write_ar_fallback_hash
        e = Emitter.new
        e << "def _write_ar_fallback_hash(aw, rs, result, attr_mask)"
        e << "  attrs = aw.attrs"
        e << "  if rs.is_indexed_row"
        e << "    ci = rs.column_indexes"
        e << "    row = rs.row"
        e << "    ah = rs.attributes_hash"
        e << "    attrs.each_with_index do |attr, i|"
        e << "      next unless attr_mask[i]"
        e << ""
        e << "      v = nil"
        e << "      am = ah[attr.name]"
        e << "      if am"
        e << "        v = am.instance_variable_get(:@value_before_type_cast)"
        e << "        attr.type ||= am.instance_variable_get(:@type)"
        e << "      end"
        e << "      if v.nil?"
        e << "        ci_val = ci[attr.name]"
        e << "        v = row[ci_val] if ci_val"
        e << "      end"
        e << "      _resolve_type(attr, rs) if attr.type.nil? && v"
        e << "      _write_value_hash(attr, v, result)"
        e << "    end"
        e << "  else"
        @attrs.each_with_index { |_attr, i| e.emit_fallback_attr_hash(i) }
        e << "  end"
        e << "end"
        e.to_source
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
