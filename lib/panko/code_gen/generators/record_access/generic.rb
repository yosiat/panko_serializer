# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    module RecordAccess
      # Generic-path Record-access emitter — used when a Descriptor's
      # +Models+ field is +nil+. Emits per Output Mode: in JSON mode the
      # +_write_one+ dispatcher plus +_write_one_hash+ / +_write_one_object+;
      # in Hash mode the parallel +_to_hash+ dispatcher plus +_to_hash_hash+ /
      # +_to_hash_object+ per +docs/output-modes.md § :hash+. Both shapes
      # branch once on +record.is_a?(Hash)+ so each helper stays monomorphic
      # end-to-end (every +record["id"]+ / +record.id+ call site sees one
      # receiver class). The Specialized counterpart lands in S6.
      module Generic
        # Emits the JSON-mode +_write_one+ dispatcher plus the two helpers
        # under +builder+. Field emit inside each helper is delegated to
        # the per-Field-kind emitters: +Attribute+, and +Association+
        # (+has_one+ landed in S5.1; +has_many+ in S5.2).
        #
        # @param descriptor [SerializersCodeGen::Descriptor] the Descriptor
        #   being compiled
        # @param config [SerializersCodeGen::Config] resolved compile-time
        #   settings; +hash_record_key_type+ selects between
        #   +record["id"]+ and +record[:id]+
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(descriptor, config, builder)
          emit_json_dispatch(builder)
          builder.blank
          emit_json_hash_helper(descriptor, config, builder)
          builder.blank
          emit_json_object_helper(descriptor, config, builder)
        end

        # Emits the Hash-mode +_to_hash+ dispatcher plus the two helpers
        # under +builder+, parallel to +emit_json+. Output keys come from
        # +Config#hash_output_key_type+; record-side Hash keys come from
        # +Config#hash_record_key_type+ — two orthogonal axes per
        # +docs/config.md+.
        #
        # @param descriptor [SerializersCodeGen::Descriptor] the Descriptor
        #   being compiled
        # @param config [SerializersCodeGen::Config] resolved settings
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash(descriptor, config, builder)
          emit_hash_dispatch(builder)
          builder.blank
          emit_hash_hash_helper(descriptor, config, builder)
          builder.blank
          emit_hash_object_helper(descriptor, config, builder)
        end

        # Emits the JSON-mode +_write_one+ dispatcher.
        #
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json_dispatch(builder)
          builder.line "def _write_one(record, writer, context, filters)"
          builder.indent do
            builder.line "if record.is_a?(Hash)"
            builder.indent { builder.line "_write_one_hash(record, writer, context, filters)" }
            builder.line "else"
            builder.indent { builder.line "_write_one_object(record, writer, context, filters)" }
            builder.line "end"
          end
          builder.line "end"
        end

        # Emits +_write_one_hash+, the JSON-mode Hash-record helper.
        # Hash-key form follows +Config#hash_record_key_type+ — String
        # literal for +:string+ (default), Symbol literal for +:symbol+.
        # Only the default branch is exercised in this slice; the +:symbol+
        # branch is exercised by the S10 config-isolation fixture.
        #
        # @param descriptor [SerializersCodeGen::Descriptor] the Descriptor
        # @param config [SerializersCodeGen::Config] resolved settings
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json_hash_helper(descriptor, config, builder)
          builder.line "def _write_one_hash(record, writer, context, filters)"
          builder.indent do
            builder.line "writer.push_object"
            descriptor.attributes.each do |attribute|
              FieldEmitters::Attribute.emit_json(attribute, hash_read_expr(attribute.source, config), builder)
            end
            descriptor.associations.each do |association|
              FieldEmitters::Association.emit_json(association, hash_read_expr(association.source, config), config, builder)
            end
            descriptor.method_attributes.each do |method_attribute|
              FieldEmitters::MethodAttribute.emit_json(method_attribute, builder)
            end
            builder.line "writer.pop"
          end
          builder.line "end"
        end

        # Emits +_write_one_object+, the JSON-mode method-dispatch helper.
        # Works for ActiveRecord instances, POROs, and anything responding
        # to the Source method.
        #
        # @param descriptor [SerializersCodeGen::Descriptor] the Descriptor
        # @param config [SerializersCodeGen::Config] resolved settings;
        #   threaded through to per-Field emitters whose source choices
        #   depend on it (e.g. +Association#emit_json+ branches on
        #   +null_for_missing_has_one+)
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json_object_helper(descriptor, config, builder)
          builder.line "def _write_one_object(record, writer, context, filters)"
          builder.indent do
            builder.line "writer.push_object"
            descriptor.attributes.each do |attribute|
              FieldEmitters::Attribute.emit_json(attribute, "record.#{attribute.source}", builder)
            end
            descriptor.associations.each do |association|
              FieldEmitters::Association.emit_json(association, "record.#{association.source}", config, builder)
            end
            descriptor.method_attributes.each do |method_attribute|
              FieldEmitters::MethodAttribute.emit_json(method_attribute, builder)
            end
            builder.line "writer.pop"
          end
          builder.line "end"
        end

        # Emits the Hash-mode +_to_hash+ dispatcher.
        #
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash_dispatch(builder)
          builder.line "def _to_hash(record, context, filters)"
          builder.indent do
            builder.line "if record.is_a?(Hash)"
            builder.indent { builder.line "_to_hash_hash(record, context, filters)" }
            builder.line "else"
            builder.indent { builder.line "_to_hash_object(record, context, filters)" }
            builder.line "end"
          end
          builder.line "end"
        end

        # Emits +_to_hash_hash+, the Hash-mode Hash-record helper. Body
        # is +result = {}; result[<key>] = record[<key>]; …; result+ per
        # +docs/output-modes.md § :hash+ — no Writer indirection. The
        # output key shape comes from +Config#hash_output_key_type+, the
        # record-side lookup from +Config#hash_record_key_type+; both
        # default to +:string+ in this slice.
        #
        # @param descriptor [SerializersCodeGen::Descriptor] the Descriptor
        # @param config [SerializersCodeGen::Config] resolved settings
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash_hash_helper(descriptor, config, builder)
          builder.line "def _to_hash_hash(record, context, filters)"
          builder.indent do
            builder.line "result = {}"
            descriptor.attributes.each do |attribute|
              FieldEmitters::Attribute.emit_hash(
                attribute,
                hash_read_expr(attribute.source, config),
                config.hash_output_key_type,
                builder
              )
            end
            descriptor.associations.each do |association|
              FieldEmitters::Association.emit_hash(
                association,
                hash_read_expr(association.source, config),
                config.hash_output_key_type,
                config,
                builder
              )
            end
            descriptor.method_attributes.each do |method_attribute|
              FieldEmitters::MethodAttribute.emit_hash(method_attribute, config.hash_output_key_type, builder)
            end
            builder.line "result"
          end
          builder.line "end"
        end

        # Emits +_to_hash_object+, the Hash-mode method-dispatch helper.
        # Works for ActiveRecord instances, POROs, and anything responding
        # to the Source method.
        #
        # @param descriptor [SerializersCodeGen::Descriptor] the Descriptor
        # @param config [SerializersCodeGen::Config] resolved settings
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash_object_helper(descriptor, config, builder)
          builder.line "def _to_hash_object(record, context, filters)"
          builder.indent do
            builder.line "result = {}"
            descriptor.attributes.each do |attribute|
              FieldEmitters::Attribute.emit_hash(
                attribute,
                "record.#{attribute.source}",
                config.hash_output_key_type,
                builder
              )
            end
            descriptor.associations.each do |association|
              FieldEmitters::Association.emit_hash(
                association,
                "record.#{association.source}",
                config.hash_output_key_type,
                config,
                builder
              )
            end
            descriptor.method_attributes.each do |method_attribute|
              FieldEmitters::MethodAttribute.emit_hash(method_attribute, config.hash_output_key_type, builder)
            end
            builder.line "result"
          end
          builder.line "end"
        end

        # Returns the Hash-record read expression for one Source name,
        # keyed by +Config#hash_record_key_type+. Shared between JSON
        # mode (+_write_one_hash+) and Hash mode (+_to_hash_hash+) — the
        # record-side lookup is mode-independent — and across Attribute
        # vs Association consumers (the source name is the only varying
        # input).
        #
        # @param source_name [Symbol] the Source method name (Attribute's
        #   or Association's +source+)
        # @param config [SerializersCodeGen::Config] resolved settings
        # @return [String] Ruby source like +"record[\"id\"]"+ or
        #   +"record[:id]"+
        def self.hash_read_expr(source_name, config)
          case config.hash_record_key_type
          when :symbol then "record[:#{source_name}]"
          else %(record["#{source_name}"])
          end
        end
      end
    end
  end
end
