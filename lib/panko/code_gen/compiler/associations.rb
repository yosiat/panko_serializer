# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates has_one and has_many association write methods.
      module Associations
        private

        def gen_write_has_one
          e = Emitter.new
          e << "def self._write_has_one(object, writer, context)"
          @has_one_assocs.each_with_index { |a, i| e.emit_has_one(i, a.name_sym, a.name_str) }
          e << "end"
          e.to_source
        end

        def gen_write_has_one_filtered
          e = Emitter.new
          e << "def self._write_has_one_filtered(object, writer, filter_mask, context)"
          e << "ho_mask = filter_mask.has_one"
          e << "ho_masks = filter_mask.has_one_masks"
          @has_one_assocs.each_with_index { |a, i| e.emit_has_one_filtered(i, a.name_sym, a.name_str) }
          e << "end"
          e.to_source
        end

        def gen_write_has_many
          e = Emitter.new
          e << "def self._write_has_many(object, writer, context)"
          @has_many_assocs.each_with_index { |a, i| e.emit_has_many(i, a.name_sym, a.name_str) }
          e << "end"
          e.to_source
        end

        def gen_write_has_many_filtered
          e = Emitter.new
          e << "def self._write_has_many_filtered(object, writer, filter_mask, context)"
          e << "hm_mask = filter_mask.has_many"
          e << "hm_masks = filter_mask.has_many_masks"
          @has_many_assocs.each_with_index { |a, i| e.emit_has_many_filtered(i, a.name_sym, a.name_str) }
          e << "end"
          e.to_source
        end
      end
    end
  end
end
