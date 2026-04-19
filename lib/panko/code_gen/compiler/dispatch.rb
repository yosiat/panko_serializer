# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates the per-serializer +_write_one+ and +_write_one_hash+
      # dispatch methods.
      #
      # These methods replace the generic dispatch previously hosted on
      # {GeneratedBase}. They:
      #
      # - compute +is_ar = object.is_a?(ActiveRecord::Base)+ once and
      #   thread it into the association emitters
      # - inline +method_fields+, +has_one+ and +has_many+ blocks instead of
      #   calling separate stub methods — emitting nothing when the serializer
      #   has no such concerns
      # - own +writer.push_object(key)+ / +writer.pop+ for the JSON path so
      #   callers (including +serialize_one+, +_serialize_many+, and parent
      #   associations) no longer need to wrap each call with push/pop
      module Dispatch
        private

        # --- JSON path ---

        def gen_write_one
          e = Emitter.new
          e << "def self._write_one(object, writer, key, filter_mask, context)"
          e << "writer.push_object(key)"
          e << "is_ar = object.is_a?(ActiveRecord::Base)"
          e << "if is_ar"
          e << "  @_ar_writer.write(object, writer, filter_mask)"
          e << "elsif object.is_a?(Hash)"
          e << "  _write_hash(object, writer, filter_mask.attrs)"
          e << "else"
          e << "  _write_plain(object, writer, filter_mask.attrs)"
          e << "end"
          emit_inline_method_fields(e) if @has_method_fields
          emit_inline_has_one(e) if @has_has_one
          emit_inline_has_many(e) if @has_has_many
          e << "writer.pop"
          e << "end"
          e.to_source
        end

        # --- Hash path ---

        def gen_write_one_hash
          e = Emitter.new
          e << "def self._write_one_hash(object, filter_mask, context)"
          e << "result = {}"
          e << "is_ar = object.is_a?(ActiveRecord::Base)"
          e << "if is_ar"
          e << "  @_ar_writer.write_hash(object, result, filter_mask)"
          e << "elsif object.is_a?(Hash)"
          e << "  _write_hash_hash(object, result, filter_mask.attrs)"
          e << "else"
          e << "  _write_plain_hash(object, result, filter_mask.attrs)"
          e << "end"
          emit_inline_method_fields_hash(e) if @has_method_fields
          emit_inline_has_one_hash(e) if @has_has_one
          emit_inline_has_many_hash(e) if @has_has_many
          e << "result"
          e << "end"
          e.to_source
        end

        def emit_inline_method_fields(e)
          e << "mf_mask = filter_mask.method_fields"
          e << "ser = @_serializer_class.new(context, object)"
          @method_fields.each_with_index { |mf, i| e.emit_method_field(i, mf.name_sym, mf.name_for_serialization) }
        end

        def emit_inline_method_fields_hash(e)
          e << "mf_mask = filter_mask.method_fields"
          e << "ser = @_serializer_class.new(context, object)"
          @method_fields.each_with_index { |mf, i| e.emit_method_field_hash(i, mf.name_sym, mf.name_for_serialization) }
        end

        def emit_inline_has_one(e)
          e << "ho_mask = filter_mask.has_one"
          e << "ho_masks = filter_mask.has_one_masks"
          @has_one_assocs.each_with_index { |a, i| e.emit_has_one(i, a.name_sym, a.name_str) }
        end

        def emit_inline_has_one_hash(e)
          e << "ho_mask = filter_mask.has_one"
          e << "ho_masks = filter_mask.has_one_masks"
          @has_one_assocs.each_with_index { |a, i| e.emit_has_one_hash(i, a.name_sym, a.name_str) }
        end

        def emit_inline_has_many(e)
          e << "hm_mask = filter_mask.has_many"
          e << "hm_masks = filter_mask.has_many_masks"
          @has_many_assocs.each_with_index { |a, i| e.emit_has_many(i, a.name_sym, a.name_str) }
        end

        def emit_inline_has_many_hash(e)
          e << "hm_mask = filter_mask.has_many"
          e << "hm_masks = filter_mask.has_many_masks"
          @has_many_assocs.each_with_index { |a, i| e.emit_has_many_hash(i, a.name_sym, a.name_str) }
        end
      end
    end
  end
end
