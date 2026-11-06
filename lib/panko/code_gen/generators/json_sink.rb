# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    class JsonSink < Sink
      def output
        :json
      end

      def suffix
        "JSON"
      end

      def entry_name
        GeneratedNames.write_one
      end

      def generic_entry_name
        GeneratedNames.generic_write_one
      end

      def split_hash_helper
        GeneratedNames.write_one_hash
      end

      def split_object_helper
        GeneratedNames.write_one_object
      end

      def entry_params
        "record, writer, context, scope, filters"
      end

      def emit_class_constants(descriptor, config, builder)
        return unless config.pool_writer
        subclass = defined?(ActiveSupport::IsolatedExecutionState) ? "IsolatedExecutionState" : "ThreadLocal"
        builder.line "POOL = Panko::CodeGen::WritersPool::#{subclass}.new"
      end

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

      def open_record(builder)
        builder.line "writer.push_object"
      end

      def close_record(builder)
        builder.line "writer.pop"
      end

      # +cast:+ exists to match {HashSink#attribute} and is ignored: Oj's +:rails+ mode formats
      # JSON values.
      def attribute(attribute, read_expr, config, index, builder, cast: true)
        builder.line "unless filters.drops?(#{index})"
        builder.indent do
          builder.line %(writer.push_value(#{read_expr}, "#{attribute.name}"))
        end
        builder.line "end"
      end

      def specialized_attribute(attribute, ar_model, config, index, builder)
        if RecordAccess::Specialized.json_column_attribute?(attribute, ar_model)
          json_column_attribute(attribute, config, index, builder)
        elsif RecordAccess::Specialized.datetime_column_attribute?(attribute, ar_model)
          datetime_column_attribute(attribute, index, builder)
        else
          attribute(attribute, RecordAccess::Specialized.attribute_read_expr(attribute, ar_model), config, index, builder)
        end
      end

      # +equal?+, not +==+, so an object that overrides +==+ cannot match +SKIP+.
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

      # +result+ starts nil so a body that raises hands checkin nil, and the writer is dropped.
      def with_writer(config, builder, &block)
        if config.pool_writer
          builder.line "writer = POOL.checkout"
          builder.line "result = nil"
          builder.line "begin"
          builder.indent(&block)
          builder.line "ensure"
          builder.indent do
            builder.line "POOL.checkin(writer, result)"
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

      # A non-nil +has_one+ pushes its key separately instead of +push_object("name")+: the
      # child's +_write_one+ opens its own +push_object+ frame.
      def has_one_default(association, builder)
        builder.line "if value.nil?"
        builder.indent { builder.line %(writer.push_value(nil, "#{association.name}")) }
        builder.line "else"
        builder.indent do
          builder.line %(writer.push_key("#{association.name}"))
          child_write(association, "value", builder) do |ivar|
            "#{ivar}.#{GeneratedNames.write_one}(value, writer, context, scope, #{child_filter_expr(association)})"
          end
        end
        builder.line "end"
      end

      def has_one_omit(association, builder)
        builder.line "unless value.nil?"
        builder.indent do
          builder.line %(writer.push_key("#{association.name}"))
          child_write(association, "value", builder) do |ivar|
            "#{ivar}.#{GeneratedNames.write_one}(value, writer, context, scope, #{child_filter_expr(association)})"
          end
        end
        builder.line "end"
      end

      def has_many(association, source_read_expr, builder)
        builder.line "child_filter = #{child_filter_expr(association)}"
        builder.line %(writer.push_array("#{association.name}"))
        builder.line "#{source_read_expr}.each do |element|"
        builder.indent do
          child_write(association, "element", builder) do |ivar|
            "#{ivar}.#{GeneratedNames.write_one}(element, writer, context, scope, child_filter)"
          end
        end
        builder.line "end"
        builder.line "writer.pop"
      end

      # Raw column bytes are pushed only after a strict parse accepts them; anything else
      # (non-String, empty, malformed) falls back to the typed read.
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
