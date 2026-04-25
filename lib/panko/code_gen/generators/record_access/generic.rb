# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    module RecordAccess
      # Generic-path Record-access emitter — used when a Descriptor's
      # +Models+ field is +nil+. Emits the +_write_one+ dispatcher plus
      # the two monomorphic helpers +_write_one_hash+ and +_write_one_object+
      # per +docs/compilation.md § Generic path — models: nil+.
      #
      # The dispatcher branches once on +record.is_a?(Hash)+ so each helper
      # is monomorphic end-to-end (every +record["id"]+ / +record.id+
      # call site sees one receiver class). The Specialized counterpart
      # lands in S6.
      module Generic
        # Emits the +_write_one+ dispatcher plus the two helpers under
        # +builder+. Field emit inside each helper is delegated to the
        # per-Field-kind emitters (this slice: +Attribute+ only).
        #
        # @param descriptor [SerializersCodeGen::Descriptor] the Descriptor
        #   being compiled
        # @param config [SerializersCodeGen::Config] resolved compile-time
        #   settings; +hash_record_key_type+ selects between
        #   +record["id"]+ and +record[:id]+
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(descriptor, config, builder)
          emit_dispatch(builder)
          builder.blank
          emit_hash_helper(descriptor, config, builder)
          builder.blank
          emit_object_helper(descriptor, builder)
        end

        # Emits the +_write_one+ dispatcher.
        #
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_dispatch(builder)
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

        # Emits +_write_one_hash+, the Hash-record helper. Hash-key form
        # follows +Config#hash_record_key_type+ — String literal for
        # +:string+ (default), Symbol literal for +:symbol+. Only the
        # default branch is exercised in this slice; the +:symbol+ branch
        # is exercised by the S10 config-isolation fixture.
        #
        # @param descriptor [SerializersCodeGen::Descriptor] the Descriptor
        # @param config [SerializersCodeGen::Config] resolved settings
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash_helper(descriptor, config, builder)
          builder.line "def _write_one_hash(record, writer, context, filters)"
          builder.indent do
            builder.line "writer.push_object"
            descriptor.attributes.each do |attribute|
              FieldEmitters::Attribute.emit_json(attribute, hash_read_expr(attribute, config), builder)
            end
            builder.line "writer.pop"
          end
          builder.line "end"
        end

        # Emits +_write_one_object+, the method-dispatch helper. Works for
        # ActiveRecord instances, POROs, and anything responding to the
        # Source method.
        #
        # @param descriptor [SerializersCodeGen::Descriptor] the Descriptor
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_object_helper(descriptor, builder)
          builder.line "def _write_one_object(record, writer, context, filters)"
          builder.indent do
            builder.line "writer.push_object"
            descriptor.attributes.each do |attribute|
              FieldEmitters::Attribute.emit_json(attribute, "record.#{attribute.source}", builder)
            end
            builder.line "writer.pop"
          end
          builder.line "end"
        end

        # Returns the Hash-record read expression for one Attribute,
        # keyed by +Config#hash_record_key_type+.
        #
        # @param attribute [SerializersCodeGen::Attribute] the Field node
        # @param config [SerializersCodeGen::Config] resolved settings
        # @return [String] Ruby source like +"record[\"id\"]"+ or
        #   +"record[:id]"+
        def self.hash_read_expr(attribute, config)
          case config.hash_record_key_type
          when :symbol then "record[:#{attribute.source}]"
          else %(record["#{attribute.source}"])
          end
        end
      end
    end
  end
end
