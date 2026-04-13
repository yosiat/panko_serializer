# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates top-level dispatch methods: _write_one and _serialize_many.
      module Dispatch
        private

        # Generates +_serialize_many+ — type dispatch once per batch,
        # then tight per-type loops with inlined extras.
        def gen_serialize_many
          has_extras = @has_method_fields || @has_has_one || @has_has_many

          e = Emitter.new
          e << "def self._serialize_many(objects, writer, key = nil, filter_mask: nil, context: nil)"
          e << "  writer.push_array(key)"
          e << "  if objects.empty?"
          e << "    writer.pop"
          e << "    return"
          e << "  end"
          e << ""
          e << "  first = objects.is_a?(Array) ? objects[0] : objects.first"

          e << "  if first.is_a?(ActiveRecord::Base)"
          emit_typed_loop(e, "@_ar_writer.write(obj, writer, filter_mask)", "@_ar_writer.write(obj, writer, nil)", has_extras, ar_path: true)

          e << "  elsif first.is_a?(Hash)"
          emit_typed_loop(e, "_write_hash_filtered(obj, writer, filter_mask.attrs)", "_write_hash(obj, writer)", has_extras)

          e << "  else"
          emit_typed_loop(e, "_write_plain_filtered(obj, writer, filter_mask.attrs)", "_write_plain(obj, writer)", has_extras)

          e << "  end"
          e << "  writer.pop"
          e << "end"
          e.to_source
        end

        def emit_typed_loop(e, filtered_write, unfiltered_write, has_extras, ar_path: false)
          if has_extras || !ar_path
            e << "    if filter_mask"
            emit_loop_body(e, filtered_write, filtered: true)
            e << "    else"
            emit_loop_body(e, unfiltered_write, filtered: false)
          else
            e << "    objects.each do |obj|"
            e << "      writer.push_object"
            e << "      #{filtered_write}"
            e << "      writer.pop"
          end
          e << "    end"
        end

        def emit_loop_body(e, write_call, filtered:)
          e << "      objects.each do |obj|"
          e << "        writer.push_object"
          e << "        #{write_call}"
          if filtered
            e << "        _write_method_fields_filtered(obj, writer, filter_mask.method_fields, context)" if @has_method_fields
            e << "        _write_has_one_filtered(obj, writer, filter_mask, context)" if @has_has_one
            e << "        _write_has_many_filtered(obj, writer, filter_mask, context)" if @has_has_many
          else
            e << "        _write_method_fields(obj, writer, context)" if @has_method_fields
            e << "        _write_has_one(obj, writer, context)" if @has_has_one
            e << "        _write_has_many(obj, writer, context)" if @has_has_many
          end
          e << "        writer.pop"
          e << "      end"
        end

        # Generates +_write_one+ — object-type dispatch + extras.
        # Only includes filter/method/association dispatch when needed.
        def gen_write_one
          has_extras = @has_method_fields || @has_has_one || @has_has_many

          extras = ""
          if has_extras
            extras = "\n    if filter_mask"
            extras += "\n      _write_method_fields_filtered(object, writer, filter_mask.method_fields, context)" if @has_method_fields
            extras += "\n      _write_has_one_filtered(object, writer, filter_mask, context)" if @has_has_one
            extras += "\n      _write_has_many_filtered(object, writer, filter_mask, context)" if @has_has_many
            extras += "\n    else"
            extras += "\n      _write_method_fields(object, writer, context)" if @has_method_fields
            extras += "\n      _write_has_one(object, writer, context)" if @has_has_one
            extras += "\n      _write_has_many(object, writer, context)" if @has_has_many
            extras += "\n    end"
          end

          <<~RUBY
            def self._write_one(object, writer, filter_mask, context)
              if object.is_a?(ActiveRecord::Base)
                @_ar_writer.write(object, writer, filter_mask)
              elsif object.is_a?(Hash)
                if filter_mask
                  _write_hash_filtered(object, writer, filter_mask.attrs)
                else
                  _write_hash(object, writer)
                end
              else
                if filter_mask
                  _write_plain_filtered(object, writer, filter_mask.attrs)
                else
                  _write_plain(object, writer)
                end
              end#{extras}
            end
          RUBY
        end
      end
    end
  end
end
