# frozen_string_literal: true

module Panko
  module CodeGen
    # Source string builder for generated serializer methods.
    #
    # Provides methods for each per-attribute code pattern. The {Compiler}
    # creates an Emitter, calls pattern methods for each attribute, and
    # retrieves the assembled source via {#to_source}.
    #
    # Never called at runtime — only during class compilation.
    class Emitter
      def initialize
        @lines = []
      end

      # Appends a raw source line.
      #
      # @param line [String] a line of Ruby source
      # @return [void]
      def <<(line)
        @lines << line
      end

      # Returns the assembled Ruby source string.
      #
      # @return [String]
      def to_source
        @lines.join("\n")
      end

      # --- Indexed cached hot path (post-warmup) ---

      # Emits one unrolled attribute read + write from the parallel caches.
      # Three-branch dispatch: direct push_value, nil, or writer.write.
      #
      # @param i [Integer] attribute index in the parallel cache arrays
      # @return [void]
      def emit_cached_attr(i)
        self << "v = row[aw.col[#{i}]]"
        self << "if aw.dir[#{i}]"
        self << "  writer.push_value(v, aw.key[#{i}])"
        self << "elsif v.nil?"
        self << "  writer.push_value(nil, aw.key[#{i}])"
        self << "else"
        self << "  aw.wtr[#{i}].write(v, writer, aw.key[#{i}])"
        self << "end"
      end

      # Emits one guarded attribute for the filtered cached path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_cached_attr_filtered(i)
        self << "if attr_mask[#{i}]"
        self << "  v = row[aw.col[#{i}]]"
        self << "  if aw.dir[#{i}]"
        self << "    writer.push_value(v, aw.key[#{i}])"
        self << "  elsif v.nil?"
        self << "    writer.push_value(nil, aw.key[#{i}])"
        self << "  else"
        self << "    aw.wtr[#{i}].write(v, writer, aw.key[#{i}])"
        self << "  end"
        self << "end"
      end

      # --- Indexed first pass (type resolution, runs once) ---

      # Emits one unrolled attribute for the first-pass type resolution path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_first_pass_attr(i)
        self << "attr = attrs[#{i}]"
        self << "ci_val = ci[attr.name]"
        self << "v = ci_val ? row[ci_val] : nil"
        self << "_resolve_type(attr, rs) if attr.type.nil? && v"
        self << "_write_value(attr, v, writer)"
      end

      # Emits one guarded attribute for the filtered first-pass path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_first_pass_attr_filtered(i)
        self << "if attr_mask[#{i}]"
        self << "  attr = attrs[#{i}]"
        self << "  ci_val = ci[attr.name]"
        self << "  v = ci_val ? row[ci_val] : nil"
        self << "  _resolve_type(attr, rs) if attr.type.nil? && v"
        self << "  _write_value(attr, v, writer)"
        self << "else"
        self << "  attr = attrs[#{i}]"
        self << "  ci_val = ci[attr.name]"
        self << "  v = ci_val ? row[ci_val] : nil"
        self << "  _resolve_type(attr, rs) if attr.type.nil? && v"
        self << "end"
      end

      # --- Indexed with dirty attributes fallback ---

      # Emits one unrolled attribute for the indexed-with-dirty-hash path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_indexed_with_hash_attr(i)
        self << "attr = attrs[#{i}]"
        self << "v = nil"
        self << "am = ah[attr.name]"
        self << "if am"
        self << "  v = am.instance_variable_get(:@value_before_type_cast)"
        self << "  attr.type ||= am.instance_variable_get(:@type)"
        self << "end"
        self << "if v.nil?"
        self << "  ci_val = ci[attr.name]"
        self << "  v = row[ci_val] if ci_val"
        self << "end"
        self << "_resolve_type(attr, rs) if attr.type.nil? && v"
        self << "_write_value(attr, v, writer)"
      end

      # Emits one guarded attribute for the filtered indexed-with-hash path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_indexed_with_hash_attr_filtered(i)
        self << "if attr_mask[#{i}]"
        self << "  attr = attrs[#{i}]"
        self << "  v = nil"
        self << "  am = ah[attr.name]"
        self << "  if am"
        self << "    v = am.instance_variable_get(:@value_before_type_cast)"
        self << "    attr.type ||= am.instance_variable_get(:@type)"
        self << "  end"
        self << "  if v.nil?"
        self << "    ci_val = ci[attr.name]"
        self << "    v = row[ci_val] if ci_val"
        self << "  end"
        self << "  _resolve_type(attr, rs) if attr.type.nil? && v"
        self << "  _write_value(attr, v, writer)"
        self << "end"
      end

      # --- Non-indexed fallback (Rails 7.x) ---

      # Emits one unrolled attribute for the non-indexed path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_non_indexed_attr(i)
        self << "v = rs.read_attribute(attrs[#{i}])"
        self << "Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attrs[#{i}], v)"
      end

      # Emits one guarded attribute for the filtered non-indexed path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_non_indexed_attr_filtered(i)
        self << "if attr_mask[#{i}]"
        self << "  v = rs.read_attribute(attrs[#{i}])"
        self << "  Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attrs[#{i}], v)"
        self << "end"
      end

      # --- Method fields ---

      # Emits one unrolled method field call with literal method name and key.
      # Assumes +ser+ (pooled serializer) is in scope with +@object+ already set.
      #
      # @param method_name [Symbol, String] the method to call on the serializer
      # @param serialization_key [String] the JSON key for the output
      # @return [void]
      def emit_method_field(method_name, serialization_key)
        self << "result = ser.#{method_name}"
        self << "writer.push_value(result, #{serialization_key.inspect}) unless result.equal?(Panko::Engine::SKIP)"
      end

      # --- Hash object ---

      # Emits one unrolled attribute read from a Hash object.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_hash_attr(i)
        self << "writer.push_value(object[attrs[#{i}].name], attrs[#{i}].name_for_serialization)"
      end

      # Emits one guarded attribute read from a Hash object.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_hash_attr_filtered(i)
        self << "if attr_mask[#{i}]"
        self << "  writer.push_value(object[attrs[#{i}].name], attrs[#{i}].name_for_serialization)"
        self << "end"
      end

      # --- Plain (PORO) object ---

      # Emits one unrolled attribute read from a plain Ruby object.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_plain_attr(i)
        self << "writer.push_value(object.public_send(attrs[#{i}].name_sym), attrs[#{i}].name_for_serialization)"
      end

      # Emits one guarded attribute read from a plain Ruby object.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_plain_attr_filtered(i)
        self << "if attr_mask[#{i}]"
        self << "  writer.push_value(object.public_send(attrs[#{i}].name_sym), attrs[#{i}].name_for_serialization)"
        self << "end"
      end

      # --- Method fields (filtered) ---

      # Emits one guarded method field call.
      # +mf_mask+ may be nil — meaning include all method fields.
      #
      # @param i [Integer] method field index
      # @param method_name [Symbol, String] the method to call on the serializer
      # @param serialization_key [String] the JSON key for the output
      # @return [void]
      def emit_method_field_filtered(i, method_name, serialization_key)
        self << "if mf_mask.nil? || mf_mask[#{i}]"
        self << "  result = ser.#{method_name}"
        self << "  writer.push_value(result, #{serialization_key.inspect}) unless result.equal?(Panko::Engine::SKIP)"
        self << "end"
      end

      # --- has_one associations ---

      # Emits one unrolled has_one association write with literal names.
      # Inlines AR association target resolution with literal method calls.
      # Passes the static sub-mask for sub-association filtering.
      #
      # @param i [Integer] association index
      # @param name_sym [Symbol] the association name (for target resolution)
      # @param name_str [String] the JSON key for the output
      # @return [void]
      def emit_has_one(i, name_sym, name_str)
        emit_has_one_target_resolution(name_sym)
        self << "if target.nil?"
        self << "  writer.push_value(nil, #{name_str.inspect})"
        self << "else"
        self << "  @_has_one_assocs[#{i}].serializer_writer._serialize_one(target, writer, #{name_str.inspect}, filter_mask: @_ho_static_masks[#{i}], context: context)"
        self << "end"
      end

      # Emits one guarded has_one association write.
      # Uses runtime nested mask if available, else falls back to static.
      #
      # @param i [Integer] association index
      # @param name_sym [Symbol] the association name
      # @param name_str [String] the JSON key
      # @return [void]
      def emit_has_one_filtered(i, name_sym, name_str)
        self << "if ho_mask.nil? || ho_mask[#{i}]"
        emit_has_one_target_resolution(name_sym, indent: "  ")
        self << "  if target.nil?"
        self << "    writer.push_value(nil, #{name_str.inspect})"
        self << "  else"
        self << "    nested = ho_masks&.dig(#{i}) || @_ho_static_masks[#{i}]"
        self << "    @_has_one_assocs[#{i}].serializer_writer._serialize_one(target, writer, #{name_str.inspect}, filter_mask: nested, context: context)"
        self << "  end"
        self << "end"
      end

      # --- has_many associations ---

      # Emits one unrolled has_many association write with literal names.
      # Passes the static sub-mask for sub-association filtering.
      #
      # @param i [Integer] association index
      # @param name_sym [Symbol] the association name
      # @param name_str [String] the JSON key for the output
      # @return [void]
      def emit_has_many(i, name_sym, name_str)
        self << "collection = object.#{name_sym}"
        self << "if collection.nil?"
        self << "  writer.push_value(nil, #{name_str.inspect})"
        self << "else"
        self << "  @_has_many_assocs[#{i}].serializer_writer._serialize_many(collection.to_a, writer, #{name_str.inspect}, filter_mask: @_hm_static_masks[#{i}], context: context)"
        self << "end"
      end

      # Emits one guarded has_many association write.
      # Uses runtime nested mask if available, else falls back to static.
      #
      # @param i [Integer] association index
      # @param name_sym [Symbol] the association name
      # @param name_str [String] the JSON key
      # @return [void]
      def emit_has_many_filtered(i, name_sym, name_str)
        self << "if hm_mask.nil? || hm_mask[#{i}]"
        self << "  collection = object.#{name_sym}"
        self << "  if collection.nil?"
        self << "    writer.push_value(nil, #{name_str.inspect})"
        self << "  else"
        self << "    nested = hm_masks&.dig(#{i}) || @_hm_static_masks[#{i}]"
        self << "    @_has_many_assocs[#{i}].serializer_writer._serialize_many(collection.to_a, writer, #{name_str.inspect}, filter_mask: nested, context: context)"
        self << "  end"
        self << "end"
      end

      private

      # Emits inline AR has_one target resolution with literal method calls.
      # Bypasses the association proxy via +association().target+ for loaded
      # AR associations. Falls back to +object.name+ for POROs or
      # method-based associations.
      #
      # @param name_sym [Symbol] the association name
      # @param indent [String] prefix for indentation
      # @return [void]
      def emit_has_one_target_resolution(name_sym, indent: "")
        self << "#{indent}if object.respond_to?(:association)"
        self << "#{indent}  begin"
        self << "#{indent}    _ar_assoc = object.association(:#{name_sym})"
        self << "#{indent}    target = _ar_assoc.loaded? ? _ar_assoc.target : object.#{name_sym}"
        self << "#{indent}  rescue ActiveRecord::AssociationNotFoundError"
        self << "#{indent}    target = object.#{name_sym}"
        self << "#{indent}  end"
        self << "#{indent}else"
        self << "#{indent}  target = object.#{name_sym}"
        self << "#{indent}end"
      end
    end
  end
end
