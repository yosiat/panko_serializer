# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    module FieldEmitters
      # Emits the +writer.push_key+ / +writer.push_value+ pair for one
      # +Attribute+ inside a +_write_one_*+ helper. The Field-level emitter
      # is mode-aware (this slice: JSON only) but Source-resolution-agnostic:
      # the read expression is supplied by the record-access strategy
      # (+RecordAccess::Generic+ here, +RecordAccess::Specialized+ in S6).
      #
      # Per +docs/code-generation.md § Generator shape+, each emitter takes
      # the descriptor node + a +CodeBuilder+ and writes lines.
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
      end
    end
  end
end
