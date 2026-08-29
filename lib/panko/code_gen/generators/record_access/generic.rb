# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    module RecordAccess
      # Generic-path Record-access emitter — used when a Descriptor's
      # +Model+ is +nil+. Emits one per-record entry whose body branches
      # once on +record.is_a?(Hash)+ with both field-emit shapes inlined
      # under the branch arms. Inlining (rather than dispatching to
      # per-shape helpers) saves a method call per record — measurable on
      # association-heavy single-record serialization — while keeping
      # every +record["id"]+ / +record.id+ call site monomorphic: each
      # branch arm owns its own call sites, so the inline caches never
      # see a mixed receiver.
      #
      # When the Descriptor declares a Symbol-body Method Attribute, the
      # body is prepended with per-record +@object+ / +@context+ /
      # +@scope+ writes so the user-defined method can read them on +self+
      # — see {emit_parent_class_ivar_writes}.
      #
      # Above {FUSED_DISPATCH_MAX_FIELDS} fields the emit reverts to the
      # dispatcher + per-shape-helper split: on very wide serializers the
      # per-record call it saves is noise while the doubled body taxes
      # method-granular JITs.
      module Generic
        # Field count above which the entry emits the dispatcher +
        # per-shape-helper split instead of the fused inline body.
        # Measured (Ruby 4.0.2 + YJIT, Struct records): fused wins
        # +4%/+3% single-record at 30/90 fields with zero side exits —
        # YJIT's lazy basic-block versioning only compiles the executed
        # arm. The split above this width trades that ~3% for halved
        # per-method source: insurance for method-granular JITs (ZJIT
        # compiles whole methods) and bounded code-region growth across
        # apps with hundreds of Generated Classes.
        FUSED_DISPATCH_MAX_FIELDS = 64

        # Emits the per-record entry under +builder+: one method, an
        # +is_a?(Hash)+ branch, both field-emit shapes inline via
        # {FieldWalk}. The record-read expression per arm is the only
        # difference between the two bodies.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @param config [Panko::CodeGen::Config] resolved settings;
        #   +hash_record_key_type+ selects between +record["id"]+ and
        #   +record[:id]+
        # @param field_index [Hash{Symbol => Integer}] codegen-time
        #   +filter key → integer index+ map
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @param sink [Panko::CodeGen::Generators::Sink] the Output Mode
        #   adapter
        # @param method_name [String] emitted method name; the default is
        #   the entry's own name, +sink.generic_entry_name+ is the
        #   guarded-Specialized twin (see {Specialized} under
        #   +Config#guarded_model+)
        # @return [void]
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

        # The above-threshold emit: the entry dispatches on the record
        # shape to the sink's two per-shape helpers, each carrying one
        # field-emit body. Same bytes per body as the fused arms — only
        # the wrapping differs.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @param config [Panko::CodeGen::Config]
        # @param field_index [Hash{Symbol => Integer}]
        # @param builder [Panko::CodeGen::CodeBuilder]
        # @param sink [Panko::CodeGen::Generators::Sink]
        # @param method_name [String] emitted dispatcher name (the
        #   per-shape helper names come from the sink)
        # @return [void]
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

        # @param descriptor [Panko::CodeGen::Descriptor]
        # @return [Boolean] whether this Descriptor's field count is over
        #   {FUSED_DISPATCH_MAX_FIELDS}
        def self.split_dispatch?(descriptor)
          descriptor.attributes.size + descriptor.method_attributes.size + descriptor.associations.size >
            FUSED_DISPATCH_MAX_FIELDS
        end

        # Prepends per-record +@object+ / +@context+ / +@scope+ ivar
        # writes when the Descriptor declares a Symbol-body Method
        # Attribute — the only code that runs on the Generated Class
        # instance during a serialize (Callable bodies receive explicit
        # args), so on descriptors without one the writes would be pure
        # per-record overhead compounding across nested Composition.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_parent_class_ivar_writes(descriptor, builder)
          return if descriptor.method_attributes.none? { |method_attribute| method_attribute.body.is_a?(Symbol) }
          builder.line "@object = record"
          builder.line "@context = context"
          builder.line "@scope = scope"
        end

        # The Hash-record read expression for one Source name, keyed by
        # +Config#hash_record_key_type+. Record-side lookup is
        # mode-independent — shared across both sinks and both Field
        # kinds.
        #
        # @param source_name [Symbol]
        # @param config [Panko::CodeGen::Config]
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
