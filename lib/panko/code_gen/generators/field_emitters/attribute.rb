# frozen_string_literal: true

module Panko::CodeGen
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
      #
      # Every per-Field emit body is wrapped in
      # +unless filters.drops?(<integer>) ... end+ per
      # +docs/filters.md § Threading through Composition+. The integer
      # literal is the Field's position in the canonical Field ordering
      # (Attributes + Method Attributes + Associations, declared order)
      # and is baked at codegen time so the runtime hot path is one
      # +Integer#[]+ / +Array#[]+ lookup against the +FIELD_INDEX+-driven
      # representation +Filter::Indexed+ chooses (S14.2). On the no-filter
      # path the wrapper resolves through +Filter::NONE.drops? → false+
      # and emits unconditionally — same bytes as phase 1 plus one
      # constant-true branch per Field.
      module Attribute
        # Emits the JSON-mode write for one Attribute. Inside the
        # +unless filters.drops?(<index>)+ wrapper, one line:
        # +writer.push_value(<read_expr>, "<name>")+ — the 2-arg form of
        # +Oj::StringWriter#push_value+ collapses a +push_key+ + +push_value+
        # pair into a single C-extension dispatch (byte-identical output,
        # identical allocations, fewer dispatches per Field).
        #
        # @param attribute [Panko::CodeGen::Attribute] the Field node
        # @param read_expr [String] Ruby source for fetching the value
        #   (e.g. +"record[\"id\"]"+ or +"record.id"+)
        # @param index [Integer] codegen-time +FIELD_INDEX+ position used
        #   in the +unless filters.drops?(<index>)+ wrapper
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(attribute, read_expr, index, builder)
          builder.line "unless filters.drops?(#{index})"
          builder.indent do
            builder.line %(writer.push_value(#{read_expr}, "#{attribute.name}"))
          end
          builder.line "end"
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
        # @param attribute [Panko::CodeGen::Attribute] the Field node;
        #   must be column-backed on the Specialized path
        # @param config [Panko::CodeGen::Config] resolved compile-time
        #   settings; +json_column_emit+ selects the emit shape
        # @param index [Integer] codegen-time +FIELD_INDEX+ position used
        #   in the +unless filters.drops?(<index>)+ wrapper
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json_column(attribute, config, index, builder)
          if config.json_column_emit == :html_safe
            emit_json(attribute, %(record._read_attribute("#{attribute.source}")), index, builder)
            return
          end
          source_lit = %("#{attribute.source}")
          key_lit = %("#{attribute.name}")
          builder.line "unless filters.drops?(#{index})"
          builder.indent do
            builder.line %(raw = record.read_attribute_before_type_cast(#{source_lit}))
            builder.line "if raw.is_a?(String) && !raw.empty? && (begin"
            builder.indent do
              builder.line "Oj.sc_parse(Panko::CodeGen::JSON_NOOP_PARSER, raw, mode: :strict)"
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
          builder.line "end"
        end

        # Emits the datetime-column write for one Attribute on the
        # Specialized path, JSON mode. Reads the pre-typecast raw bytes and
        # splices them into the ISO-8601 shape via
        # {Panko::CodeGen::DateTimeFormat.format_raw} — skipping AR's
        # String→Time→TimeWithZone cast and Oj's Time formatting entirely.
        # Any unrecognized raw value (dirty attribute holding a Time, nil,
        # exotic adapter format) falls back to pushing the type-cast read,
        # today's shape. Routed only when the column is uniformly
        # datetime-typed AND +::ActiveRecord.default_timezone == :utc+ (the
        # raw bytes carry no zone; only under +:utc+ is the trailing "Z"
        # truthful) — see +RecordAccess::Specialized+.
        #
        # @param attribute [Panko::CodeGen::Attribute] the Field node;
        #   must be a datetime column on the Specialized path
        # @param index [Integer] codegen-time +FIELD_INDEX+ position used
        #   in the +unless filters.drops?(<index>)+ wrapper
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json_datetime_column(attribute, index, builder)
          source_lit = %("#{attribute.source}")
          builder.line "unless filters.drops?(#{index})"
          builder.indent do
            builder.line "value = Panko::CodeGen::DateTimeFormat.format_raw(record.read_attribute_before_type_cast(#{source_lit}))"
            builder.line %(writer.push_value(value || record._read_attribute(#{source_lit}), "#{attribute.name}"))
          end
          builder.line "end"
        end

        # Emits the datetime-column write for one Attribute on the
        # Specialized path, Hash mode — the Hash-mode twin of
        # {.emit_json_datetime_column}. The fallback wraps the type-cast
        # read in +cast_datetime+ so the Hash-mode datetime→String contract
        # holds on the slow path too.
        #
        # @param attribute [Panko::CodeGen::Attribute] the Field node;
        #   must be a datetime column on the Specialized path
        # @param output_key_type [Symbol] +:string+ or +:symbol+ — the
        #   pre-validated value of +Config#hash_output_key_type+
        # @param index [Integer] codegen-time +FIELD_INDEX+ position used
        #   in the +unless filters.drops?(<index>)+ wrapper
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash_datetime_column(attribute, output_key_type, index, builder)
          source_lit = %("#{attribute.source}")
          builder.line "unless filters.drops?(#{index})"
          builder.indent do
            builder.line "value = Panko::CodeGen::DateTimeFormat.format_raw(record.read_attribute_before_type_cast(#{source_lit}))"
            builder.line "result[#{hash_key_literal(attribute, output_key_type)}] = value || " \
              "Panko::CodeGen.cast_datetime(record._read_attribute(#{source_lit}))"
          end
          builder.line "end"
        end

        # Emits the Hash-mode write for one Attribute. Inside the
        # +unless filters.drops?(<index>)+ wrapper, one line:
        # +result[<key>] = Panko::CodeGen.cast_datetime(<read_expr>)+ — the
        # cast reproduces Panko's C-ext datetime→ISO-8601 String formatting for
        # Hash mode (a no-op for non-datetime values). The output-key shape comes from
        # +output_key_type+ — +:string+ (default) emits +result["id"]+,
        # +:symbol+ emits +result[:id]+. Only the +:string+ branch is
        # exercised in S3.1; the +:symbol+ branch is pinned by S10's
        # +config_hash_output_key_symbol+ fixture.
        #
        # When the caller can prove at compile time the value is never a
        # datetime (a plain-typed column on the Specialized path), +cast:
        # false+ drops the wrapper and assigns the read directly — the
        # wrapper sits on every Hash-mode field write, so eliding it where
        # types are known is a measurable win.
        #
        # @param attribute [Panko::CodeGen::Attribute] the Field node
        # @param read_expr [String] Ruby source for fetching the value
        #   (e.g. +"record[\"id\"]"+ or +"record.id"+)
        # @param output_key_type [Symbol] +:string+ or +:symbol+ — the
        #   pre-validated value of +Config#hash_output_key_type+
        # @param index [Integer] codegen-time +FIELD_INDEX+ position used
        #   in the +unless filters.drops?(<index>)+ wrapper
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @param cast [Boolean] wrap the read in +cast_datetime+ (default);
        #   +false+ only when the value is provably not a datetime
        # @return [void]
        def self.emit_hash(attribute, read_expr, output_key_type, index, builder, cast: true)
          value_expr = cast ? "Panko::CodeGen.cast_datetime(#{read_expr})" : read_expr
          builder.line "unless filters.drops?(#{index})"
          builder.indent do
            builder.line "result[#{hash_key_literal(attribute, output_key_type)}] = #{value_expr}"
          end
          builder.line "end"
        end

        # @param attribute [Panko::CodeGen::Attribute] the Field node
        # @param output_key_type [Symbol] +:string+ or +:symbol+
        # @return [String] the Hash-mode output-key literal
        def self.hash_key_literal(attribute, output_key_type)
          case output_key_type
          when :symbol then ":#{attribute.name}"
          else %("#{attribute.name}")
          end
        end
      end
    end
  end
end
