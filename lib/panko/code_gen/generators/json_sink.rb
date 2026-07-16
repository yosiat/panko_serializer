# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # The +:json+ adapter at the Output Mode seam: every JSON-divergent
    # emit shape in one place. Values flow through an +Oj::StringWriter+
    # threaded positionally through the generated call tree; the 2-arg
    # +push_value(v, "k")+ / +push_array("k")+ forms collapse a
    # +push_key+ + opener pair into a single C-extension dispatch. The
    # non-nil +has_one+ arms keep the +push_key+ + nested-call split —
    # the inner +_write_one+ opens its own +push_object+ frame, so
    # collapsing across that boundary would require restructuring the
    # +_write_one+ contract.
    class JsonSink < Sink
      # @return [Symbol]
      def output
        :json
      end

      # @return [String]
      def suffix
        "JSON"
      end

      # @return [String]
      def entry_name
        GeneratedNames.write_one
      end

      # @return [String]
      def generic_entry_name
        GeneratedNames.generic_write_one
      end

      # @return [String]
      def split_hash_helper
        GeneratedNames.write_one_hash
      end

      # @return [String]
      def split_object_helper
        GeneratedNames.write_one_object
      end

      # @return [String] the positional signature the per-record entry
      #   points share — JSON threads the Writer between record and context
      def entry_params
        "record, writer, context, scope, filters"
      end

      # Emits the +POOL+ constant when +Config#pool_writer+ is set. The
      # WritersPool subclass is selected once at Compile time: when
      # Rails 7.0+ is loaded, AR ConnectionPool keys off
      # +ActiveSupport::IsolatedExecutionState+, and aligning the pool's
      # locality with that constant gives fiber-isolated servers (Falcon)
      # the right semantics; otherwise +Thread.current[]+ (fiber-local in
      # MRI) is the safe default.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @param config [Panko::CodeGen::Config]
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def emit_class_constants(descriptor, config, builder)
        return unless config.pool_writer
        subclass = defined?(ActiveSupport::IsolatedExecutionState) ? "IsolatedExecutionState" : "ThreadLocal"
        builder.line "POOL = Panko::CodeGen::WritersPool::#{subclass}.new(#{GeneratedNames.writer_pool_key(descriptor).inspect})"
      end

      # Emits the public +serialize_one+: acquire a Writer (pooled or
      # fresh), thread it through the per-record entry, return the
      # chomped String. With +Config#supports_root_key+ the signature
      # gains +root_key:+ and the body wraps the emit in a
      # +push_object+ / +push_key+ frame — +push_key(root_key)+ cannot
      # collapse into a 2-arg +push_object+ because the inner entry opens
      # its own frame.
      #
      # @param config [Panko::CodeGen::Config]
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def emit_serialize_one(config, builder)
        signature = config.supports_root_key ?
          "def serialize_one(record, context: nil, scope: nil, filters: nil, root_key: nil)" :
          "def serialize_one(record, context: nil, scope: nil, filters: nil)"
        builder.line signature
        builder.indent do
          builder.line "filters = Panko::CodeGen::Filter.wrap(filters, #{GeneratedNames.field_index_const})"
          if config.supports_root_key
            builder.line "validate_root_key!(root_key)"
          end
          with_writer(config, builder) { emit_serialize_one_body(config, builder) }
        end
        builder.line "end"
      end

      # Emits the public +serialize_many+: same Writer lifecycle as
      # {#emit_serialize_one} around a +push_array+ frame, so an empty
      # collection still emits +[]+ (wrapped as +{"<root>":[]}+ under a
      # root key — never +null+, never omitted).
      #
      # @param config [Panko::CodeGen::Config]
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def emit_serialize_many(config, builder)
        signature = config.supports_root_key ?
          "def serialize_many(records, context: nil, scope: nil, filters: nil, root_key: nil)" :
          "def serialize_many(records, context: nil, scope: nil, filters: nil)"
        builder.line signature
        builder.indent do
          builder.line "filters = Panko::CodeGen::Filter.wrap(filters, #{GeneratedNames.field_index_const})"
          if config.supports_root_key
            builder.line "validate_root_key!(root_key)"
          end
          with_writer(config, builder) { emit_serialize_many_body(config, builder) }
        end
        builder.line "end"
      end

      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def open_record(builder)
        builder.line "writer.push_object"
      end

      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def close_record(builder)
        builder.line "writer.pop"
      end

      # Emits one Attribute write: +writer.push_value(<read_expr>, "<name>")+
      # inside the filter wrapper. +cast:+ is accepted for interface parity
      # with {HashSink#attribute} and ignored — Oj's +:rails+ mode owns
      # JSON-side value formatting.
      #
      # @param attribute [Panko::CodeGen::Attribute]
      # @param read_expr [String]
      # @param config [Panko::CodeGen::Config]
      # @param index [Integer] the Field's +FIELD_INDEX+ position
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @param cast [Boolean] ignored in JSON mode
      # @return [void]
      def attribute(attribute, read_expr, config, index, builder, cast: true)
        builder.line "unless filters.drops?(#{index})"
        builder.indent do
          builder.line %(writer.push_value(#{read_expr}, "#{attribute.name}"))
        end
        builder.line "end"
      end

      # Emits one Attribute on the Specialized path, dispatching on the
      # column classification: JSON-typed columns take the +:wire_format+
      # raw-bytes path, datetime columns the raw-splice path, everything
      # else the plain typed read.
      #
      # @param attribute [Panko::CodeGen::Attribute]
      # @param ar_model [Class, nil]
      # @param config [Panko::CodeGen::Config]
      # @param index [Integer]
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def specialized_attribute(attribute, ar_model, config, index, builder)
        if RecordAccess::Specialized.json_column_attribute?(attribute, ar_model)
          json_column_attribute(attribute, config, index, builder)
        elsif RecordAccess::Specialized.datetime_column_attribute?(attribute, ar_model)
          datetime_column_attribute(attribute, index, builder)
        else
          attribute(attribute, RecordAccess::Specialized.attribute_read_expr(attribute, ar_model), config, index, builder)
        end
      end

      # Emits one Method Attribute write: invoke the body, identity-compare
      # against +SKIP+ (+equal?+, never +==+ — an +==+-overriding object
      # must not collide with the sentinel), then push.
      #
      # @param method_attribute [Panko::CodeGen::MethodAttribute]
      # @param config [Panko::CodeGen::Config]
      # @param index [Integer]
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def method_attribute(method_attribute, config, index, builder)
        builder.line "unless filters.drops?(#{index})"
        builder.indent do
          builder.line "value = #{method_attribute_call_expression(method_attribute)}"
          builder.line "unless value.equal?(Panko::CodeGen::SKIP)"
          builder.indent do
            builder.line %(writer.push_value(value, "#{method_attribute.name}"))
          end
          builder.line "end"
        end
        builder.line "end"
      end

      # Emits one Association write, dispatching on Kind inside the
      # filter wrapper and optional +if:+ guard.
      #
      # @param association [Panko::CodeGen::Association]
      # @param source_read_expr [String]
      # @param config [Panko::CodeGen::Config]
      # @param index [Integer]
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def association(association, source_read_expr, config, index, builder)
        builder.line "unless filters.drops?(#{index})"
        builder.indent do
          with_if_guard(association, builder) do
            case association.kind
            when :has_one
              builder.line "value = #{source_read_expr}"
              if config.null_for_missing_has_one
                has_one_default(association, builder)
              else
                has_one_omit(association, builder)
              end
            when :has_many
              has_many(association, source_read_expr, builder)
            end
          end
        end
        builder.line "end"
      end

      private

      # Emits the writer acquisition around +block+: pooled
      # (+POOL.checkout+ / +ensure POOL.checkin+) or a fresh
      # +Oj::StringWriter+ per call. One helper so the two paths' bytes
      # can only diverge on the wrap, not the inner emit.
      def with_writer(config, builder, &block)
        if config.pool_writer
          builder.line "writer = POOL.checkout"
          builder.line "begin"
          builder.indent(&block)
          builder.line "ensure"
          builder.indent do
            builder.line "POOL.checkin(writer)"
          end
          builder.line "end"
        else
          builder.line "writer = Oj::StringWriter.new(mode: :rails)"
          yield
        end
      end

      def emit_serialize_one_body(config, builder)
        if config.supports_root_key
          builder.line "if root_key"
          builder.indent do
            builder.line "writer.push_object"
            builder.line "writer.push_key(root_key)"
          end
          builder.line "end"
        end
        builder.line "#{GeneratedNames.write_one}(record, writer, context, scope, filters)"
        builder.line "writer.pop if root_key" if config.supports_root_key
        builder.line "result = writer.to_s"
        builder.line "result.chomp!"
        builder.line "result"
      end

      def emit_serialize_many_body(config, builder)
        if config.supports_root_key
          builder.line "writer.push_object if root_key"
          builder.line "writer.push_array(root_key)"
        else
          builder.line "writer.push_array"
        end
        builder.line "records.each { |r| #{GeneratedNames.write_one}(r, writer, context, scope, filters) }"
        builder.line "writer.pop"
        builder.line "writer.pop if root_key" if config.supports_root_key
        builder.line "result = writer.to_s"
        builder.line "result.chomp!"
        builder.line "result"
      end

      # The nil arm collapses key+value into the 2-arg
      # +push_value(nil, "<name>")+; the non-nil arm pushes the key and
      # dispatches into the nested Generated Class.
      def has_one_default(association, builder)
        builder.line "if value.nil?"
        builder.indent { builder.line %(writer.push_value(nil, "#{association.name}")) }
        builder.line "else"
        builder.indent do
          builder.line %(writer.push_key("#{association.name}"))
          builder.line "#{GeneratedNames.serializer_ivar(association)}.#{GeneratedNames.write_one}" \
            "(value, writer, context, scope, #{child_filter_expr(association)})"
        end
        builder.line "end"
      end

      # +null_for_missing_has_one: false+ — omit the key entirely when
      # the Source returns nil.
      def has_one_omit(association, builder)
        builder.line "unless value.nil?"
        builder.indent do
          builder.line %(writer.push_key("#{association.name}"))
          builder.line "#{GeneratedNames.serializer_ivar(association)}.#{GeneratedNames.write_one}" \
            "(value, writer, context, scope, #{child_filter_expr(association)})"
        end
        builder.line "end"
      end

      # +child_filter+ is hoisted above the iteration so the Filter
      # cell's child cache is consulted once per (Association, Record)
      # pair rather than once per element. An empty collection naturally
      # emits +[]+ — config-independent.
      def has_many(association, source_read_expr, builder)
        builder.line "child_filter = #{child_filter_expr(association)}"
        builder.line %(writer.push_array("#{association.name}"))
        builder.line "#{source_read_expr}.each do |element|"
        builder.indent do
          builder.line "#{GeneratedNames.serializer_ivar(association)}.#{GeneratedNames.write_one}" \
            "(element, writer, context, scope, child_filter)"
        end
        builder.line "end"
        builder.line "writer.pop"
      end

      # The +:wire_format+ JSON-column path: read the pre-typecast raw
      # bytes, validate well-formedness with a no-op strict parse, and
      # push them verbatim via +push_json+ — matching Panko 0.8.5
      # byte-for-byte. Any rejection (non-String, empty, malformed,
      # unsaved in-memory Hash) falls through to the typed read, so the
      # engine degrades cleanly where the 0.8.5 C extension crashed.
      # +:html_safe+ keeps the typed-read shape for consumers embedding
      # JSON in HTML without a sanitizer.
      def json_column_attribute(attribute, config, index, builder)
        if config.json_column_emit == :html_safe
          attribute(attribute, %(record._read_attribute("#{attribute.source}")), config, index, builder)
          return
        end
        source_lit = %("#{attribute.source}")
        key_lit = %("#{attribute.name}")
        builder.line "unless filters.drops?(#{index})"
        builder.indent do
          builder.line %(raw = record.read_attribute_before_type_cast(#{source_lit}))
          builder.line "if raw.is_a?(String) && !raw.empty? && (begin"
          builder.indent do
            builder.line "Oj.sc_parse(Panko::CodeGen::JSON_NOOP_PARSER, raw, Panko::CodeGen::JSON_STRICT_PARSE_OPTS)"
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

      # The datetime-column raw-splice path: format the pre-typecast raw
      # bytes straight to ISO-8601, skipping AR's String→Time cast and
      # Oj's Time formatting. Unrecognized raw values fall back to the
      # typed read. Routed only under +::ActiveRecord.default_timezone ==
      # :utc+ — the raw bytes carry no zone, so only there is the spliced
      # trailing "Z" truthful.
      def datetime_column_attribute(attribute, index, builder)
        source_lit = %("#{attribute.source}")
        builder.line "unless filters.drops?(#{index})"
        builder.indent do
          builder.line "value = Panko::CodeGen::DateTimeFormat.format_raw(record.read_attribute_before_type_cast(#{source_lit}))"
          builder.line %(writer.push_value(value || record._read_attribute(#{source_lit}), "#{attribute.name}"))
        end
        builder.line "end"
      end
    end
  end
end
