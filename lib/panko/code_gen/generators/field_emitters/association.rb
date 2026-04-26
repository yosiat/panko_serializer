# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    module FieldEmitters
      # Emits the per-mode write for one +Association+ inside a
      # +_write_one_*+ / +_to_hash_*+ helper. Composition shape per
      # +docs/compilation.md § Composition of nested Associations+: the
      # parent's constructor has hoisted +@<name>_serializer+ pointing at
      # an instance of the nested Generated Class; the emit here calls
      # through that ivar.
      #
      # S5.1 ships +has_one+ only; the +has_many+ Kind lands in S5.2 and
      # the +Association#if+ Callable wrapping lands in S5.3. Both
      # +null_for_missing_has_one+ branches (default-+true+ → emit
      # +null+/+nil+; +false+ → omit the key) are emitted as compile-time
      # source choices keyed off +Config#null_for_missing_has_one+. The
      # +false+ branch is exercised end-to-end by S10's
      # +config_null_for_has_one_off+ fixture; this slice only pins the
      # default-+true+ branch.
      module Association
        # Emits the JSON-mode write for one +has_one+ Association.
        #
        # Default (+null_for_missing_has_one: true+) emits:
        #   value = <source_read_expr>
        #   writer.push_key("<name>")
        #   if value.nil?
        #     writer.push_value(nil)
        #   else
        #     @<name>_serializer._write_one(value, writer, context, filters)
        #   end
        #
        # +null_for_missing_has_one: false+ (omit-when-nil) emits:
        #   value = <source_read_expr>
        #   unless value.nil?
        #     writer.push_key("<name>")
        #     @<name>_serializer._write_one(value, writer, context, filters)
        #   end
        #
        # @param association [SerializersCodeGen::Association] the Field node
        # @param source_read_expr [String] Ruby source for fetching the
        #   related Record (e.g. +"record[\"author\"]"+ or +"record.author"+)
        # @param config [SerializersCodeGen::Config] resolved settings;
        #   +null_for_missing_has_one+ selects the emit branch
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(association, source_read_expr, config, builder)
          builder.line "value = #{source_read_expr}"
          if config.null_for_missing_has_one
            emit_json_has_one_default(association, builder)
          else
            emit_json_has_one_omit(association, builder)
          end
        end

        # Emits the Hash-mode write for one +has_one+ Association.
        # Output-key shape comes from +output_key_type+ (the
        # +Config#hash_output_key_type+ value); only +:string+ is
        # exercised in this slice (S10 covers +:symbol+).
        #
        # Default (+null_for_missing_has_one: true+) emits:
        #   value = <source_read_expr>
        #   result[<key>] = if value.nil?
        #     nil
        #   else
        #     @<name>_serializer._to_hash(value, context, filters)
        #   end
        #
        # +null_for_missing_has_one: false+ (omit-when-nil) emits:
        #   value = <source_read_expr>
        #   unless value.nil?
        #     result[<key>] = @<name>_serializer._to_hash(value, context, filters)
        #   end
        #
        # @param association [SerializersCodeGen::Association] the Field node
        # @param source_read_expr [String] Ruby source for fetching the
        #   related Record
        # @param output_key_type [Symbol] +:string+ or +:symbol+ — the
        #   pre-validated value of +Config#hash_output_key_type+
        # @param config [SerializersCodeGen::Config] resolved settings;
        #   +null_for_missing_has_one+ selects the emit branch
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash(association, source_read_expr, output_key_type, config, builder)
          key_lit = case output_key_type
          when :symbol then ":#{association.name}"
          else %("#{association.name}")
          end
          builder.line "value = #{source_read_expr}"
          if config.null_for_missing_has_one
            emit_hash_has_one_default(association, key_lit, builder)
          else
            emit_hash_has_one_omit(association, key_lit, builder)
          end
        end

        # Emits the JSON-mode default-true branch — writes the key
        # unconditionally, then +null+ or the nested call.
        #
        # @param association [SerializersCodeGen::Association]
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_json_has_one_default(association, builder)
          builder.line %(writer.push_key("#{association.name}"))
          builder.line "if value.nil?"
          builder.indent { builder.line "writer.push_value(nil)" }
          builder.line "else"
          builder.indent do
            builder.line "@#{association.name}_serializer._write_one(value, writer, context, filters)"
          end
          builder.line "end"
        end

        # Emits the JSON-mode +null_for_missing_has_one: false+ branch
        # — omits the key entirely (no +push_key+, no +push_value+) when
        # the Source returns +nil+.
        #
        # @param association [SerializersCodeGen::Association]
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_json_has_one_omit(association, builder)
          builder.line "unless value.nil?"
          builder.indent do
            builder.line %(writer.push_key("#{association.name}"))
            builder.line "@#{association.name}_serializer._write_one(value, writer, context, filters)"
          end
          builder.line "end"
        end

        # Emits the Hash-mode default-true branch — assigns the key with
        # +nil+ or the nested call via the +result[k] = if/else/end+
        # idiom.
        #
        # @param association [SerializersCodeGen::Association]
        # @param key_lit [String] pre-rendered Ruby literal for the
        #   output key (e.g. +'"author"'+ or +':author'+)
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_hash_has_one_default(association, key_lit, builder)
          builder.line "result[#{key_lit}] = if value.nil?"
          builder.indent { builder.line "nil" }
          builder.line "else"
          builder.indent do
            builder.line "@#{association.name}_serializer._to_hash(value, context, filters)"
          end
          builder.line "end"
        end

        # Emits the Hash-mode +null_for_missing_has_one: false+ branch
        # — omits the key entirely (no assignment to +result+) when the
        # Source returns +nil+.
        #
        # @param association [SerializersCodeGen::Association]
        # @param key_lit [String] pre-rendered Ruby literal for the
        #   output key
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_hash_has_one_omit(association, key_lit, builder)
          builder.line "unless value.nil?"
          builder.indent do
            builder.line "result[#{key_lit}] = @#{association.name}_serializer._to_hash(value, context, filters)"
          end
          builder.line "end"
        end
      end
    end
  end
end
