# frozen_string_literal: true

module Panko
  module CodeGen
    class Emitter
      # Emit methods for has_one and has_many association writes.
      #
      # These emitters are inlined into the per-serializer +_write_one+ /
      # +_write_one_hash+ bodies. They rely on three locals being in scope:
      #
      # - +is_ar+ — boolean, true when +object.is_a?(ActiveRecord::Base)+
      # - +ho_mask+ / +hm_mask+ — inclusion mask for this level
      # - +ho_masks+ / +hm_masks+ — nested override masks (may be +NIL_SLOTS+)
      module Associations
        # --- has_one (JSON path) ---

        def emit_has_one(i, name_sym, name_str)
          self << "if ho_mask[#{i}]"
          emit_has_one_target_resolution(name_sym, indent: "  ")
          self << "  if target.nil?"
          self << "    writer.push_value(nil, #{name_str.inspect})"
          self << "  else"
          self << "    nested = ho_masks[#{i}] || @_ho_static_masks[#{i}]"
          self << "    @_has_one_assocs[#{i}].serializer_writer._write_one(target, writer, #{name_str.inspect}, nested, context)"
          self << "  end"
          self << "end"
        end

        # --- has_many (JSON path) ---

        def emit_has_many(i, name_sym, name_str)
          self << "if hm_mask[#{i}]"
          self << "  collection = object.#{name_sym}"
          self << "  if collection.nil?"
          self << "    writer.push_value(nil, #{name_str.inspect})"
          self << "  else"
          self << "    _sub = @_has_many_assocs[#{i}].serializer_writer"
          self << "    _mask = hm_masks[#{i}] || @_hm_static_masks[#{i}]"
          self << "    writer.push_array(#{name_str.inspect})"
          self << "    collection.each { |_el| _sub._write_one(_el, writer, nil, _mask, context) }"
          self << "    writer.pop"
          self << "  end"
          self << "end"
        end

        # --- has_one (Hash path) ---

        def emit_has_one_hash(i, name_sym, name_str)
          self << "if ho_mask[#{i}]"
          emit_has_one_target_resolution(name_sym, indent: "  ")
          self << "  if target.nil?"
          self << "    result[#{name_str.inspect}] = nil"
          self << "  else"
          self << "    nested = ho_masks[#{i}] || @_ho_static_masks[#{i}]"
          self << "    result[#{name_str.inspect}] = @_has_one_assocs[#{i}].serializer_writer._write_one_hash(target, nested, context)"
          self << "  end"
          self << "end"
        end

        # --- has_many (Hash path) ---

        def emit_has_many_hash(i, name_sym, name_str)
          self << "if hm_mask[#{i}]"
          self << "  collection = object.#{name_sym}"
          self << "  if collection.nil?"
          self << "    result[#{name_str.inspect}] = nil"
          self << "  else"
          self << "    _sub = @_has_many_assocs[#{i}].serializer_writer"
          self << "    _mask = hm_masks[#{i}] || @_hm_static_masks[#{i}]"
          self << "    result[#{name_str.inspect}] = collection.map { |_el| _sub._write_one_hash(_el, _mask, context) }"
          self << "  end"
          self << "end"
        end

        private

        # Emits inline has_one target resolution with literal method calls.
        # Uses the caller-provided +is_ar+ local so the +is_a?(ActiveRecord::Base)+
        # check is done once per object, not per association.
        def emit_has_one_target_resolution(name_sym, indent: "")
          self << "#{indent}if is_ar && object.class.reflect_on_association(:#{name_sym})"
          self << "#{indent}  _ar_assoc = object.association(:#{name_sym})"
          self << "#{indent}  target = _ar_assoc.loaded? ? _ar_assoc.target : object.#{name_sym}"
          self << "#{indent}else"
          self << "#{indent}  target = object.#{name_sym}"
          self << "#{indent}end"
        end
      end
    end
  end
end
