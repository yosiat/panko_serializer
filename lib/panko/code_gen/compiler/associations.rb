# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates has_one and has_many write methods.
      # All methods include mask guards for unified filtered/unfiltered handling.
      module Associations
        private

        # --- JSON path ---

        def gen_write_has_one
          e = Emitter.new
          e << "def self._write_has_one(object, writer, filter_mask, context)"
          e << "ho_mask = filter_mask.has_one"
          e << "ho_masks = filter_mask.has_one_masks"
          @has_one_assocs.each_with_index { |a, i| e.emit_has_one(i, a.name_sym, a.name_str) }
          e << "end"
          e.to_source
        end

        def gen_write_has_many
          e = Emitter.new
          e << "def self._write_has_many(object, writer, filter_mask, context)"
          e << "hm_mask = filter_mask.has_many"
          e << "hm_masks = filter_mask.has_many_masks"
          @has_many_assocs.each_with_index { |a, i| e.emit_has_many(i, a.name_sym, a.name_str) }
          e << "end"
          e.to_source
        end

        # --- Hash path ---

        def gen_write_has_one_hash
          e = Emitter.new
          e << "def self._write_has_one_hash(object, result, filter_mask, context)"
          e << "ho_mask = filter_mask.has_one"
          e << "ho_masks = filter_mask.has_one_masks"
          @has_one_assocs.each_with_index { |a, i| e.emit_has_one_hash(i, a.name_sym, a.name_str) }
          e << "end"
          e.to_source
        end

        def gen_write_has_many_hash
          e = Emitter.new
          e << "def self._write_has_many_hash(object, result, filter_mask, context)"
          e << "hm_mask = filter_mask.has_many"
          e << "hm_masks = filter_mask.has_many_masks"
          @has_many_assocs.each_with_index { |a, i| e.emit_has_many_hash(i, a.name_sym, a.name_str) }
          e << "end"
          e.to_source
        end
      end
    end
  end
end
