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
      # S5.1 shipped +has_one+; S5.2 adds +has_many+ (collection emit:
      # +writer.push_array+ + element iteration + +writer.pop+ in JSON;
      # +.map+ on the collection in Hash). +Association#if+ Callable
      # wrapping lands in S5.3. Both +null_for_missing_has_one+ branches
      # (default-+true+ → emit +null+/+nil+; +false+ → omit the key) are
      # emitted as compile-time source choices keyed off
      # +Config#null_for_missing_has_one+ for the +has_one+ Kind only;
      # +has_many+ ignores the knob (an empty collection always emits
      # +[]+ — never +null+, never omitted) per
      # +docs/output-modes.md § Null Association handling+. The
      # +null_for_missing_has_one: false+ branch is exercised end-to-end
      # by S10's +config_null_for_has_one_off+ fixture; this slice only
      # pins the default-+true+ branch.
      module Association
        # Emits the JSON-mode write for one Association, dispatching on
        # +association.kind+ to the per-Kind helper.
        #
        # +has_one+ — default (+null_for_missing_has_one: true+) emits:
        #   value = <source_read_expr>
        #   writer.push_key("<name>")
        #   if value.nil?
        #     writer.push_value(nil)
        #   else
        #     @<name>_serializer._write_one(value, writer, context, filters)
        #   end
        #
        # +has_one+ — omit-when-nil (+null_for_missing_has_one: false+) emits:
        #   value = <source_read_expr>
        #   unless value.nil?
        #     writer.push_key("<name>")
        #     @<name>_serializer._write_one(value, writer, context, filters)
        #   end
        #
        # +has_many+ emits (config-independent — empty collection → +[]+):
        #   writer.push_key("<name>")
        #   writer.push_array
        #   <source_read_expr>.each do |element|
        #     @<name>_serializer._write_one(element, writer, context, filters)
        #   end
        #   writer.pop
        #
        # @param association [SerializersCodeGen::Association] the Field node
        # @param source_read_expr [String] Ruby source for fetching the
        #   related Record(s) (e.g. +"record[\"author\"]"+ or
        #   +"record.comments"+)
        # @param config [SerializersCodeGen::Config] resolved settings;
        #   +null_for_missing_has_one+ selects the +has_one+ emit branch
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(association, source_read_expr, config, builder)
          case association.kind
          when :has_one
            builder.line "value = #{source_read_expr}"
            if config.null_for_missing_has_one
              emit_json_has_one_default(association, builder)
            else
              emit_json_has_one_omit(association, builder)
            end
          when :has_many
            emit_json_has_many(association, source_read_expr, builder)
          end
        end

        # Emits the Hash-mode write for one Association, dispatching on
        # +association.kind+ to the per-Kind helper. Output-key shape
        # comes from +output_key_type+ (the +Config#hash_output_key_type+
        # value); only +:string+ is exercised in this slice (S10 covers
        # +:symbol+).
        #
        # +has_one+ — default (+null_for_missing_has_one: true+) emits:
        #   value = <source_read_expr>
        #   result[<key>] = if value.nil?
        #     nil
        #   else
        #     @<name>_serializer._to_hash(value, context, filters)
        #   end
        #
        # +has_one+ — omit-when-nil (+null_for_missing_has_one: false+) emits:
        #   value = <source_read_expr>
        #   unless value.nil?
        #     result[<key>] = @<name>_serializer._to_hash(value, context, filters)
        #   end
        #
        # +has_many+ emits (config-independent — empty collection → +[]+):
        #   result[<key>] = <source_read_expr>.map { |element| @<name>_serializer._to_hash(element, context, filters) }
        #
        # @param association [SerializersCodeGen::Association] the Field node
        # @param source_read_expr [String] Ruby source for fetching the
        #   related Record(s)
        # @param output_key_type [Symbol] +:string+ or +:symbol+ — the
        #   pre-validated value of +Config#hash_output_key_type+
        # @param config [SerializersCodeGen::Config] resolved settings;
        #   +null_for_missing_has_one+ selects the +has_one+ emit branch
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash(association, source_read_expr, output_key_type, config, builder)
          key_lit = case output_key_type
          when :symbol then ":#{association.name}"
          else %("#{association.name}")
          end
          case association.kind
          when :has_one
            builder.line "value = #{source_read_expr}"
            if config.null_for_missing_has_one
              emit_hash_has_one_default(association, key_lit, builder)
            else
              emit_hash_has_one_omit(association, key_lit, builder)
            end
          when :has_many
            emit_hash_has_many(association, source_read_expr, key_lit, builder)
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

        # Emits the JSON-mode +has_many+ shape — opens an array on the
        # Writer, iterates the Source collection element-by-element
        # through the nested Generated Class's +_write_one+, then closes
        # the array. An empty collection naturally emits +[]+ (no key
        # omission, no +null+ — empty array is its own state) per
        # +docs/output-modes.md § Null Association handling+.
        #
        # @param association [SerializersCodeGen::Association]
        # @param source_read_expr [String] Ruby source for the parent
        #   Record's collection-returning Source (inlined into the
        #   +.each+ — no per-element local needed)
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_json_has_many(association, source_read_expr, builder)
          builder.line %(writer.push_key("#{association.name}"))
          builder.line "writer.push_array"
          builder.line "#{source_read_expr}.each do |element|"
          builder.indent do
            builder.line "@#{association.name}_serializer._write_one(element, writer, context, filters)"
          end
          builder.line "end"
          builder.line "writer.pop"
        end

        # Emits the Hash-mode +has_many+ shape — assigns a fresh
        # +Array<Hash>+ via +.map+ over the Source collection, each
        # element passed through the nested Generated Class's
        # +_to_hash+. An empty collection emits an empty Array (the
        # +Array#map+ on +[]+ returns +[]+) per
        # +docs/output-modes.md § Null Association handling+.
        #
        # @param association [SerializersCodeGen::Association]
        # @param source_read_expr [String] Ruby source for the parent
        #   Record's collection-returning Source
        # @param key_lit [String] pre-rendered Ruby literal for the
        #   output key
        # @param builder [SerializersCodeGen::CodeBuilder]
        # @return [void]
        def self.emit_hash_has_many(association, source_read_expr, key_lit, builder)
          builder.line(
            "result[#{key_lit}] = #{source_read_expr}.map { |element| " \
              "@#{association.name}_serializer._to_hash(element, context, filters) }"
          )
        end
      end
    end
  end
end
