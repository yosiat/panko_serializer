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
        # Emits the JSON-mode write for one Attribute. One line:
        # +writer.push_value(<read_expr>, "<name>")+ — the 2-arg form of
        # +Oj::StringWriter#push_value+ collapses a +push_key+ + +push_value+
        # pair into a single C-extension dispatch (byte-identical output,
        # identical allocations, fewer dispatches per Field).
        #
        # @param attribute [SerializersCodeGen::Attribute] the Field node
        # @param read_expr [String] Ruby source for fetching the value
        #   (e.g. +"record[\"id\"]"+ or +"record.id"+)
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(attribute, read_expr, builder)
          builder.line %(writer.push_value(#{read_expr}, "#{attribute.name}"))
        end

        # Emits the JSON-mode write for one AR-JSON-column Attribute on the
        # Specialized record-access path. Shape is selected at +Compile+
        # time by +config.json_column_emit+:
        #
        # - +:wire_format+ (default) — read the pre-typecast raw bytes via
        #   +record.read_attribute_before_type_cast(name)+, validate
        #   well-formedness via +Oj.sc_parse(JSON_NOOP_PARSER, raw, mode:
        #   :strict)+ inside an inline +rescue Oj::ParseError, EncodingError+
        #   guard, and on success push the bytes verbatim through
        #   +writer.push_json(raw, "<name>")+ — matches Panko 0.8.5
        #   byte-for-byte. On any rejection (non-String, empty, malformed,
        #   in-memory unsaved Hash, etc.) falls through to today's
        #   +writer.push_value(record._read_attribute("<name>"), "<name>")+
        #   slow path so the per-edge-case behavior is "scg degrades cleanly
        #   where Panko crashes" per
        #   +docs/research/phase_1_report.md § 8.1+.
        # - +:html_safe+ — delegates back to {.emit_json}, keeping today's
        #   +push_value(_read_attribute(...), "<name>")+ shape. Used when
        #   the consumer embeds scg output directly in HTML script tags
        #   without a sanitizer at the HTML layer; documented as opt-in in
        #   +docs/config.md+.
        #
        # Routed only on the Specialized path's column-backed Attributes —
        # see +RecordAccess::Specialized+. Generic-path Descriptors keep
        # today's +emit_json+ shape regardless of the column type.
        #
        # @param attribute [SerializersCodeGen::Attribute] the Field node;
        #   must be column-backed on the Specialized path
        # @param config [SerializersCodeGen::Config] resolved compile-time
        #   settings; +json_column_emit+ selects the emit shape
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json_column(attribute, config, builder)
          if config.json_column_emit == :html_safe
            emit_json(attribute, %(record._read_attribute("#{attribute.source}")), builder)
            return
          end
          source_lit = %("#{attribute.source}")
          key_lit = %("#{attribute.name}")
          builder.line %(raw = record.read_attribute_before_type_cast(#{source_lit}))
          builder.line "if raw.is_a?(String) && !raw.empty? && (begin"
          builder.indent do
            builder.line "Oj.sc_parse(SerializersCodeGen::JSON_NOOP_PARSER, raw, mode: :strict)"
            builder.line "true"
          end
          builder.line "rescue Oj::ParseError, EncodingError"
          builder.indent do
            builder.line "false"
          end
          builder.line "end)"
          builder.indent do
            builder.line "writer.push_json(raw, #{key_lit})"
          end
          builder.line "else"
          builder.indent do
            builder.line "writer.push_value(record._read_attribute(#{source_lit}), #{key_lit})"
          end
          builder.line "end"
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
