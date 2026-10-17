# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    module RecordAccess
      # Both field bodies are inlined under one +is_a?(Hash)+ branch: this saves a call per record,
      # and each arm owns its call sites, so a Hash and an object never share one inline cache.
      module Generic
        # Above this field count the two bodies go into separate helper methods, which halves each
        # method's size for JITs that compile whole methods (ZJIT).
        FUSED_DISPATCH_MAX_FIELDS = 64

        def self.emit(descriptor, config, field_index, builder, sink, method_name: sink.entry_name)
          return emit_split(descriptor, config, field_index, builder, sink, method_name: method_name) if split_dispatch?(descriptor)

          builder.line "def #{method_name}(#{sink.entry_params})"
          builder.indent do
            emit_parent_class_ivar_writes(descriptor, builder)
            builder.line "if record.is_a?(Hash)"
            builder.indent do
              FieldWalk.emit_fields(
                descriptor, config, field_index, builder, sink,
                read_expr: ->(source) { hash_read_expr(source, config) }
              )
            end
            builder.line "else"
            builder.indent do
              FieldWalk.emit_fields(
                descriptor, config, field_index, builder, sink,
                read_expr: ->(source) { "record.#{source}" }
              )
            end
            builder.line "end"
          end
          builder.line "end"
        end

        def self.emit_split(descriptor, config, field_index, builder, sink, method_name: sink.entry_name)
          builder.line "def #{method_name}(#{sink.entry_params})"
          builder.indent do
            emit_parent_class_ivar_writes(descriptor, builder)
            builder.line "if record.is_a?(Hash)"
            builder.indent { builder.line "#{sink.split_hash_helper}(#{sink.entry_params})" }
            builder.line "else"
            builder.indent { builder.line "#{sink.split_object_helper}(#{sink.entry_params})" }
            builder.line "end"
          end
          builder.line "end"
          builder.blank
          builder.line "def #{sink.split_hash_helper}(#{sink.entry_params})"
          builder.indent do
            FieldWalk.emit_fields(
              descriptor, config, field_index, builder, sink,
              read_expr: ->(source) { hash_read_expr(source, config) }
            )
          end
          builder.line "end"
          builder.blank
          builder.line "def #{sink.split_object_helper}(#{sink.entry_params})"
          builder.indent do
            FieldWalk.emit_fields(
              descriptor, config, field_index, builder, sink,
              read_expr: ->(source) { "record.#{source}" }
            )
          end
          builder.line "end"
        end

        def self.split_dispatch?(descriptor)
          descriptor.attributes.size + descriptor.method_attributes.size + descriptor.associations.size >
            FUSED_DISPATCH_MAX_FIELDS
        end

        # Only a Symbol-body Method Attribute reads +@object+ / +@context+ / +@scope+ on +self+;
        # Callable bodies get them as arguments, so without one the writes are wasted work per record.
        def self.emit_parent_class_ivar_writes(descriptor, builder)
          return if descriptor.method_attributes.none? { |method_attribute| method_attribute.body.is_a?(Symbol) }
          builder.line "@object = record"
          builder.line "@context = context"
          builder.line "@scope = scope"
        end

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
