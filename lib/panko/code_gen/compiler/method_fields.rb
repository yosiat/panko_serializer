# frozen_string_literal: true

module Panko
  module CodeGen
    class Compiler
      # Generates method field write methods.
      # All methods accept +mf_mask+ for unified filtered/unfiltered handling.
      module MethodFields
        private

        def gen_write_method_fields
          e = Emitter.new
          e << "def self._write_method_fields(object, writer, mf_mask, context)"
          e << "ser = @_serializer"
          e << "ser.serialization_context = context"
          e << "ser.instance_variable_set(:@object, object)"
          @method_fields.each_with_index { |mf, i| e.emit_method_field(i, mf.name_sym, mf.name_for_serialization) }
          e << "end"
          e.to_source
        end

        def gen_write_method_fields_hash
          e = Emitter.new
          e << "def self._write_method_fields_hash(object, result, mf_mask, context)"
          e << "ser = @_serializer"
          e << "ser.serialization_context = context"
          e << "ser.instance_variable_set(:@object, object)"
          @method_fields.each_with_index { |mf, i| e.emit_method_field_hash(i, mf.name_sym, mf.name_for_serialization) }
          e << "end"
          e.to_source
        end
      end
    end
  end
end
