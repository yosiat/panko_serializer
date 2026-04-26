# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    module FieldEmitters
      # Emits the per-mode write for one +Attribute+ inside a
      # +_write_one_*+ / +_to_hash_*+ helper. The Field-level emitter is
      # mode-aware (one entry per Output Mode) but Source-resolution-
      # agnostic: the read expression is supplied by the record-access
      # strategy (+RecordAccess::Generic+ here, +RecordAccess::Specialized+
      # in S6).
      #
      # Per +docs/code-generation.md § Generator shape+, each emitter takes
      # the descriptor node + a +CodeBuilder+ and writes lines. Both
      # +emit_json+ and +emit_hash+ share the same module so per-mode
      # divergence stays in one file rather than copy-pasted across the
      # codebase.
      module Attribute
        # Emits the JSON-mode write for one Attribute. Two lines:
        # +writer.push_key("<name>")+ and +writer.push_value(<read_expr>)+.
        #
        # @param attribute [SerializersCodeGen::Attribute] the Field node
        # @param read_expr [String] Ruby source for fetching the value
        #   (e.g. +"record[\"id\"]"+ or +"record.id"+)
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(attribute, read_expr, builder)
          builder.line %(writer.push_key("#{attribute.name}"))
          builder.line "writer.push_value(#{read_expr})"
        end

        # Emits the Hash-mode write for one Attribute. One line:
        # +result[<key>] = <read_expr>+. The output-key shape comes from
        # +output_key_type+ — +:string+ (default) emits +result["id"]+,
        # +:symbol+ emits +result[:id]+. Only the +:string+ branch is
        # exercised in S3.1; the +:symbol+ branch is pinned by S10's
        # +config_hash_output_key_symbol+ fixture.
        #
        # @param attribute [SerializersCodeGen::Attribute] the Field node
        # @param read_expr [String] Ruby source for fetching the value
        #   (e.g. +"record[\"id\"]"+ or +"record.id"+)
        # @param output_key_type [Symbol] +:string+ or +:symbol+ — the
        #   pre-validated value of +Config#hash_output_key_type+
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash(attribute, read_expr, output_key_type, builder)
          key_lit = case output_key_type
          when :symbol then ":#{attribute.name}"
          else %("#{attribute.name}")
          end
          builder.line "result[#{key_lit}] = #{read_expr}"
        end
      end
    end
  end
end
