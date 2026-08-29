# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # The +:hash+ adapter at the Output Mode seam: every Hash-divergent
    # emit shape in one place. No Writer — values assign into a +result+
    # Hash and datetime values funnel through +Panko::CodeGen.cast_datetime+
    # (JSON mode delegates that formatting to Oj's +:rails+ mode), so the
    # two modes' leaf values can only diverge where an adapter explicitly
    # says so.
    class HashSink < Sink
      # @return [Symbol]
      def output
        :hash
      end

      # @return [String]
      def suffix
        "Hash"
      end

      # @return [String]
      def entry_name
        GeneratedNames.to_hash
      end

      # @return [String]
      def generic_entry_name
        GeneratedNames.generic_to_hash
      end

      # @return [String]
      def split_hash_helper
        GeneratedNames.to_hash_hash
      end

      # @return [String]
      def split_object_helper
        GeneratedNames.to_hash_object
      end

      # @return [String] the positional signature the per-record entry
      #   points share — Hash mode threads no Writer
      def entry_params
        "record, context, scope, filters"
      end

      # Hash mode emits no per-class constants beyond +FIELD_INDEX+.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @param config [Panko::CodeGen::Config]
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def emit_class_constants(descriptor, config, builder)
      end

      # Emits the public +serialize_one+ — a straight delegate to the
      # per-record entry; a truthy +root_key:+ wraps the produced Hash in
      # a single-entry +{root_key => result}+.
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
            builder.line "result = #{GeneratedNames.to_hash}(record, context, scope, filters)"
            builder.line "root_key ? {root_key => result} : result"
          else
            builder.line "#{GeneratedNames.to_hash}(record, context, scope, filters)"
          end
        end
        builder.line "end"
      end

      # Emits the public +serialize_many+ — +.map+ over the input; an
      # empty input under a root key still emits +{root_key => []}+.
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
            builder.line "result = records.map { |r| #{GeneratedNames.to_hash}(r, context, scope, filters) }"
            builder.line "root_key ? {root_key => result} : result"
          else
            builder.line "records.map { |r| #{GeneratedNames.to_hash}(r, context, scope, filters) }"
          end
        end
        builder.line "end"
      end

      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def open_record(builder)
        builder.line "result = {}"
      end

      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def close_record(builder)
        builder.line "result"
      end

      # Emits one Attribute write:
      # +result[<key>] = Panko::CodeGen.cast_datetime(<read_expr>)+. The
      # cast reproduces the 0.8.5 datetime→ISO-8601 String contract (a
      # no-op for non-datetime values); +cast: false+ drops the wrapper
      # when the caller can prove at compile time the value is never a
      # datetime — the wrapper sits on every Hash-mode field write, so
      # eliding it where types are known is a measurable win.
      #
      # @param attribute [Panko::CodeGen::Attribute]
      # @param read_expr [String]
      # @param config [Panko::CodeGen::Config]
      # @param index [Integer] the Field's +FIELD_INDEX+ position
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @param cast [Boolean] wrap the read in +cast_datetime+ (default)
      # @return [void]
      def attribute(attribute, read_expr, config, index, builder, cast: true)
        value_expr = cast ? "Panko::CodeGen.cast_datetime(#{read_expr})" : read_expr
        builder.line "unless filters.drops?(#{index})"
        builder.indent do
          builder.line "result[#{key_literal(attribute.name, config)}] = #{value_expr}"
        end
        builder.line "end"
      end

      # Emits one Attribute on the Specialized path: datetime columns
      # take the raw-splice path; everything else the typed read, with
      # the +cast_datetime+ wrapper elided for provably-non-datetime
      # columns.
      #
      # @param attribute [Panko::CodeGen::Attribute]
      # @param ar_model [Class, nil]
      # @param config [Panko::CodeGen::Config]
      # @param index [Integer]
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @return [void]
      def specialized_attribute(attribute, ar_model, config, index, builder)
        if RecordAccess::Specialized.datetime_column_attribute?(attribute, ar_model)
          datetime_column_attribute(attribute, config, index, builder)
        else
          attribute(
            attribute,
            RecordAccess::Specialized.attribute_read_expr(attribute, ar_model),
            config,
            index,
            builder,
            cast: !RecordAccess::Specialized.plain_column_attribute?(attribute, ar_model)
          )
        end
      end

      # Emits one Method Attribute write — same +SKIP+ identity-compare
      # as the JSON adapter, assigning through the +cast_datetime+ funnel.
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
            builder.line "result[#{key_literal(method_attribute.name, config)}] = Panko::CodeGen.cast_datetime(value)"
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
        key_lit = key_literal(association.name, config)
        builder.line "unless filters.drops?(#{index})"
        builder.indent do
          with_if_guard(association, builder) do
            case association.kind
            when :has_one
              builder.line "value = #{source_read_expr}"
              if config.null_for_missing_has_one
                has_one_default(association, key_lit, builder)
              else
                has_one_omit(association, key_lit, builder)
              end
            when :has_many
              has_many(association, source_read_expr, key_lit, builder)
            end
          end
        end
        builder.line "end"
      end

      private

      # The output-key literal for one Field name, keyed by
      # +Config#hash_output_key_type+ — +:string+ (default) or +:symbol+.
      def key_literal(name, config)
        case config.hash_output_key_type
        when :symbol then ":#{name}"
        else %("#{name}")
        end
      end

      def has_one_default(association, key_lit, builder)
        builder.line "result[#{key_lit}] = if value.nil?"
        builder.indent { builder.line "nil" }
        builder.line "else"
        builder.indent do
          builder.line "#{GeneratedNames.serializer_ivar(association)}.#{GeneratedNames.to_hash}" \
            "(value, context, scope, #{child_filter_expr(association)})"
        end
        builder.line "end"
      end

      def has_one_omit(association, key_lit, builder)
        builder.line "unless value.nil?"
        builder.indent do
          builder.line "result[#{key_lit}] = #{GeneratedNames.serializer_ivar(association)}." \
            "#{GeneratedNames.to_hash}(value, context, scope, #{child_filter_expr(association)})"
        end
        builder.line "end"
      end

      # +child_filter+ hoisted for the same one-lookup-per-record reason
      # as the JSON adapter; +.map+ on an empty collection returns +[]+.
      def has_many(association, source_read_expr, key_lit, builder)
        builder.line "child_filter = #{child_filter_expr(association)}"
        builder.line(
          "result[#{key_lit}] = #{source_read_expr}.map { |element| " \
            "#{GeneratedNames.serializer_ivar(association)}.#{GeneratedNames.to_hash}(element, context, scope, child_filter) }"
        )
      end

      # The datetime-column raw-splice path (Hash twin of the JSON
      # adapter's): the fallback wraps the typed read in +cast_datetime+
      # so the datetime→String contract holds on the slow path too.
      def datetime_column_attribute(attribute, config, index, builder)
        source_lit = %("#{attribute.source}")
        builder.line "unless filters.drops?(#{index})"
        builder.indent do
          builder.line "value = Panko::CodeGen::DateTimeFormat.format_raw(record.read_attribute_before_type_cast(#{source_lit}))"
          builder.line "result[#{key_literal(attribute.name, config)}] = value || " \
            "Panko::CodeGen.cast_datetime(record._read_attribute(#{source_lit}))"
        end
        builder.line "end"
      end
    end
  end
end
