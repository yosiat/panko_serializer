# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates top-level dispatch methods: _write_one, _write_one_hash,
      # and _serialize_many. filter_mask is always non-nil
      # ({FilterMask::EMPTY} for unfiltered calls).
      module Dispatch
        private

        # Generates +_serialize_many+ — type dispatch once per batch,
        # then tight per-type loops.
        def gen_serialize_many
          e = Emitter.new
          e << "def self._serialize_many(objects, writer, key, filter_mask, context)"
          e << "  writer.push_array(key)"
          e << "  if objects.empty?"
          e << "    writer.pop"
          e << "    return"
          e << "  end"
          e << ""
          e << "  first = objects.is_a?(Array) ? objects[0] : objects.first"

          e << "  if first.is_a?(ActiveRecord::Base)"
          emit_loop_body(e, "@_ar_writer.write(obj, writer, filter_mask)")

          e << "  elsif first.is_a?(Hash)"
          emit_loop_body(e, "_write_hash(obj, writer, filter_mask.attrs)")

          e << "  else"
          emit_loop_body(e, "_write_plain(obj, writer, filter_mask.attrs)")

          e << "  end"
          e << "  writer.pop"
          e << "end"
          e.to_source
        end

        def emit_loop_body(e, write_call)
          e << "    objects.each do |obj|"
          e << "      writer.push_object"
          e << "      #{write_call}"
          e << "      _write_method_fields(obj, writer, filter_mask.method_fields, context)" if @has_method_fields
          e << "      _write_has_one(obj, writer, filter_mask, context)" if @has_has_one
          e << "      _write_has_many(obj, writer, filter_mask, context)" if @has_has_many
          e << "      writer.pop"
          e << "    end"
        end

        # Generates +_write_one+ — object-type dispatch + extras.
        def gen_write_one
          extras = ""
          if @has_method_fields || @has_has_one || @has_has_many
            extras += "\n    _write_method_fields(object, writer, filter_mask.method_fields, context)" if @has_method_fields
            extras += "\n    _write_has_one(object, writer, filter_mask, context)" if @has_has_one
            extras += "\n    _write_has_many(object, writer, filter_mask, context)" if @has_has_many
          end

          <<~RUBY
            def self._write_one(object, writer, filter_mask, context)
              if object.is_a?(ActiveRecord::Base)
                @_ar_writer.write(object, writer, filter_mask)
              elsif object.is_a?(Hash)
                _write_hash(object, writer, filter_mask.attrs)
              else
                _write_plain(object, writer, filter_mask.attrs)
              end#{extras}
            end
          RUBY
        end

        # Generates +_write_one_hash+ — builds a Ruby Hash directly.
        def gen_write_one_hash
          extras = ""
          if @has_method_fields || @has_has_one || @has_has_many
            extras += "\n    _write_method_fields_hash(object, result, filter_mask.method_fields, context)" if @has_method_fields
            extras += "\n    _write_has_one_hash(object, result, filter_mask, context)" if @has_has_one
            extras += "\n    _write_has_many_hash(object, result, filter_mask, context)" if @has_has_many
          end

          <<~RUBY
            def self._write_one_hash(object, filter_mask, context)
              result = {}
              if object.is_a?(ActiveRecord::Base)
                @_ar_writer.write_hash(object, result, filter_mask)
              elsif object.is_a?(Hash)
                _write_hash_hash(object, result, filter_mask.attrs)
              else
                _write_plain_hash(object, result, filter_mask.attrs)
              end#{extras}
              result
            end
          RUBY
        end
      end
    end
  end
end
