# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    module RecordAccess
      # Generic-path Record-access emitter — used when a Descriptor's
      # +Models+ field is +nil+. Emits one +_write_one+ (JSON) / +_to_hash+
      # (Hash) whose body branches once on +record.is_a?(Hash)+ with both
      # field-emit shapes inlined under the branch arms. Inlining (rather
      # than dispatching to per-shape +_write_one_hash+ / +_write_one_object+
      # helpers) saves a method call per record — measurable on
      # association-heavy single-record serialization — while keeping every
      # +record["id"]+ / +record.id+ call site monomorphic: each branch arm
      # owns its own call sites, so the inline caches never see a mixed
      # receiver. The Specialized counterpart (single shape, no branch)
      # lives in {Specialized}.
      #
      # When +descriptor.parent_class+ is non-+nil+ (S18.3) *and* the
      # Descriptor declares a Symbol-body Method Attribute, the body is
      # prepended with +@object = record; @context = context;
      # @scope = scope+ so the user-defined method can read those ivars on
      # +self+ — the Panko-shape contract from
      # +docs/code_gen/merging-into-panko.md § Generated Class subclasses the
      # user's Panko serializer+. See {emit_parent_class_ivar_writes} for
      # the gating rationale. Bare descriptors (no +parent_class:+) keep
      # the pre-S18 body shape.
      #
      # Above {FUSED_DISPATCH_MAX_FIELDS} fields the emit reverts to the
      # dispatcher + per-shape-helper split: inlining doubles the method's
      # source, and on very wide serializers the per-record call it saves
      # is noise while the doubled body taxes method-granular JITs (ZJIT
      # compiles whole methods; YJIT's lazy basic-block versioning only
      # compiles executed blocks, but code-region budget is finite across
      # hundreds of Generated Classes).
      module Generic
        # Field count above which +_write_one+ / +_to_hash+ emit the
        # dispatcher + per-shape-helper split instead of the fused inline
        # body. Measured (Ruby 4.0.2 + YJIT, Struct records): fused wins
        # +4%/+3% single-record at 30/90 fields and ~+2% on batches, with
        # zero side exits even at 90 fields — YJIT's lazy basic-block
        # versioning only compiles the executed arm, so the inline body is
        # never a compilation liability there. The split above this width
        # trades that measured ~3% for halved per-method source: insurance
        # for method-granular JITs (ZJIT compiles whole methods; untestable
        # here — this build ships without ZJIT) and for bounded code-region
        # growth across apps with hundreds of Generated Classes.
        FUSED_DISPATCH_MAX_FIELDS = 64
        # Emits the JSON-mode +_write_one+ under +builder+: one method,
        # +is_a?(Hash)+ branch, both field-emit shapes inline. +scope+
        # slots between +context+ and +filters+ in the positional
        # signature per S17.2 — Field emitters that delegate into nested
        # Composition thread the same +scope+ unchanged into the inner
        # +_write_one+. Field emit inside each arm is delegated to the
        # per-Field-kind emitters: +Attribute+, +Association+, and
        # +MethodAttribute+.
        #
        # @param descriptor [Panko::CodeGen::Descriptor] the Descriptor
        #   being compiled
        # @param config [Panko::CodeGen::Config] resolved compile-time
        #   settings; +hash_record_key_type+ selects between
        #   +record["id"]+ and +record[:id]+
        # @param field_index [Hash{Symbol => Integer}] codegen-time
        #   +filter key → integer index+ map per
        #   +docs/code_gen/filters.md § Threading through Composition+; threaded
        #   into each +FieldEmitters::*.emit_*+ call so the emitted
        #   +unless filters.drops?(<integer>)+ wrapper bakes the
        #   per-Field literal at codegen time
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @param method_name [String] emitted method name; the default is
        #   the Generic path's own entry, +"_generic_write_one"+ is the
        #   guarded-Specialized twin (see {Specialized} under
        #   +Config#guarded_model+)
        # @return [void]
        def self.emit_json(descriptor, config, field_index, builder, method_name: GeneratedNames.write_one)
          return emit_json_split(descriptor, config, field_index, builder, method_name: method_name) if split_dispatch?(descriptor)

          builder.line "def #{method_name}(record, writer, context, scope, filters)"
          builder.indent do
            emit_parent_class_ivar_writes(descriptor, builder)
            builder.line "if record.is_a?(Hash)"
            builder.indent { emit_json_fields(descriptor, config, field_index, builder) { |source| hash_read_expr(source, config) } }
            builder.line "else"
            builder.indent { emit_json_fields(descriptor, config, field_index, builder) { |source| "record.#{source}" } }
            builder.line "end"
          end
          builder.line "end"
        end

        # The above-threshold JSON emit: +_write_one+ dispatches on the
        # record shape to +_write_one_hash+ / +_write_one_object+, each
        # carrying one field-emit body. Same bytes per body as the fused
        # arms — only the wrapping differs.
        #
        # @param descriptor [Panko::CodeGen::Descriptor] the Descriptor
        # @param config [Panko::CodeGen::Config] resolved settings
        # @param field_index [Hash{Symbol => Integer}] codegen-time
        #   +filter key → integer index+ map
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @param method_name [String] emitted dispatcher name (the
        #   per-shape helper names are fixed)
        # @return [void]
        def self.emit_json_split(descriptor, config, field_index, builder, method_name: GeneratedNames.write_one)
          builder.line "def #{method_name}(record, writer, context, scope, filters)"
          builder.indent do
            emit_parent_class_ivar_writes(descriptor, builder)
            builder.line "if record.is_a?(Hash)"
            builder.indent { builder.line "#{GeneratedNames.write_one_hash}(record, writer, context, scope, filters)" }
            builder.line "else"
            builder.indent { builder.line "#{GeneratedNames.write_one_object}(record, writer, context, scope, filters)" }
            builder.line "end"
          end
          builder.line "end"
          builder.blank
          builder.line "def #{GeneratedNames.write_one_hash}(record, writer, context, scope, filters)"
          builder.indent { emit_json_fields(descriptor, config, field_index, builder) { |source| hash_read_expr(source, config) } }
          builder.line "end"
          builder.blank
          builder.line "def #{GeneratedNames.write_one_object}(record, writer, context, scope, filters)"
          builder.indent { emit_json_fields(descriptor, config, field_index, builder) { |source| "record.#{source}" } }
          builder.line "end"
        end

        # Emits the Hash-mode +_to_hash+ under +builder+, parallel to
        # {emit_json}. Output keys come from +Config#hash_output_key_type+;
        # record-side Hash keys come from +Config#hash_record_key_type+ —
        # two orthogonal axes per +docs/code_gen/config.md+.
        #
        # @param descriptor [Panko::CodeGen::Descriptor] the Descriptor
        #   being compiled
        # @param config [Panko::CodeGen::Config] resolved settings
        # @param field_index [Hash{Symbol => Integer}] codegen-time
        #   +filter key → integer index+ map; threaded into each
        #   +FieldEmitters::*.emit_*+ call (mirror of {emit_json})
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @param method_name [String] emitted method name; +"_generic_to_hash"+
        #   is the guarded-Specialized twin (mirror of {emit_json})
        # @return [void]
        def self.emit_hash(descriptor, config, field_index, builder, method_name: GeneratedNames.to_hash)
          return emit_hash_split(descriptor, config, field_index, builder, method_name: method_name) if split_dispatch?(descriptor)

          builder.line "def #{method_name}(record, context, scope, filters)"
          builder.indent do
            emit_parent_class_ivar_writes(descriptor, builder)
            builder.line "if record.is_a?(Hash)"
            builder.indent { emit_hash_fields(descriptor, config, field_index, builder) { |source| hash_read_expr(source, config) } }
            builder.line "else"
            builder.indent { emit_hash_fields(descriptor, config, field_index, builder) { |source| "record.#{source}" } }
            builder.line "end"
          end
          builder.line "end"
        end

        # The above-threshold Hash emit — mirror of {emit_json_split}.
        #
        # @param descriptor [Panko::CodeGen::Descriptor] the Descriptor
        # @param config [Panko::CodeGen::Config] resolved settings
        # @param field_index [Hash{Symbol => Integer}] codegen-time
        #   +filter key → integer index+ map
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @param method_name [String] emitted dispatcher name (the
        #   per-shape helper names are fixed)
        # @return [void]
        def self.emit_hash_split(descriptor, config, field_index, builder, method_name: GeneratedNames.to_hash)
          builder.line "def #{method_name}(record, context, scope, filters)"
          builder.indent do
            emit_parent_class_ivar_writes(descriptor, builder)
            builder.line "if record.is_a?(Hash)"
            builder.indent { builder.line "#{GeneratedNames.to_hash_hash}(record, context, scope, filters)" }
            builder.line "else"
            builder.indent { builder.line "#{GeneratedNames.to_hash_object}(record, context, scope, filters)" }
            builder.line "end"
          end
          builder.line "end"
          builder.blank
          builder.line "def #{GeneratedNames.to_hash_hash}(record, context, scope, filters)"
          builder.indent { emit_hash_fields(descriptor, config, field_index, builder) { |source| hash_read_expr(source, config) } }
          builder.line "end"
          builder.blank
          builder.line "def #{GeneratedNames.to_hash_object}(record, context, scope, filters)"
          builder.indent { emit_hash_fields(descriptor, config, field_index, builder) { |source| "record.#{source}" } }
          builder.line "end"
        end

        # @param descriptor [Panko::CodeGen::Descriptor]
        # @return [Boolean] whether this Descriptor's field count is over
        #   {FUSED_DISPATCH_MAX_FIELDS}
        def self.split_dispatch?(descriptor)
          descriptor.attributes.size + descriptor.method_attributes.size + descriptor.associations.size >
            FUSED_DISPATCH_MAX_FIELDS
        end

        # Emits one JSON-mode field-emit body (+push_object+ … +pop+)
        # into +builder+ — one branch arm of {emit_json}. The record-read
        # expression for each Source comes from the block, so the Hash arm
        # and the method-dispatch arm share this emit verbatim.
        #
        # @param descriptor [Panko::CodeGen::Descriptor] the Descriptor
        # @param config [Panko::CodeGen::Config] resolved settings
        # @param field_index [Hash{Symbol => Integer}] codegen-time
        #   +filter key → integer index+ map
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @yieldparam source [Symbol] a Field's Source name
        # @yieldreturn [String] the record-read expression for it
        # @return [void]
        def self.emit_json_fields(descriptor, config, field_index, builder, &read_expr)
          builder.line "writer.push_object"
          descriptor.attributes.each do |attribute|
            FieldEmitters::Attribute.emit_json(
              attribute, read_expr.call(attribute.source), field_index.fetch(GeneratedNames.filter_key(attribute)), builder
            )
          end
          descriptor.associations.each do |association|
            FieldEmitters::Association.emit_json(
              association, read_expr.call(association.source), config,
              field_index.fetch(GeneratedNames.filter_key(association)), builder
            )
          end
          descriptor.method_attributes.each do |method_attribute|
            FieldEmitters::MethodAttribute.emit_json(
              method_attribute, field_index.fetch(GeneratedNames.filter_key(method_attribute)), builder
            )
          end
          builder.line "writer.pop"
        end

        # Emits one Hash-mode field-emit body (+result = {}+ … +result+,
        # no Writer indirection per +docs/code_gen/output-modes.md § :hash+) into
        # +builder+ — one branch arm of {emit_hash}. The record-read
        # expression for each Source comes from the block, mirroring
        # {emit_json_fields}.
        #
        # @param descriptor [Panko::CodeGen::Descriptor] the Descriptor
        # @param config [Panko::CodeGen::Config] resolved settings
        # @param field_index [Hash{Symbol => Integer}] codegen-time
        #   +filter key → integer index+ map
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @yieldparam source [Symbol] a Field's Source name
        # @yieldreturn [String] the record-read expression for it
        # @return [void]
        def self.emit_hash_fields(descriptor, config, field_index, builder, &read_expr)
          builder.line "result = {}"
          descriptor.attributes.each do |attribute|
            FieldEmitters::Attribute.emit_hash(
              attribute,
              read_expr.call(attribute.source),
              config.hash_output_key_type,
              field_index.fetch(GeneratedNames.filter_key(attribute)),
              builder
            )
          end
          descriptor.associations.each do |association|
            FieldEmitters::Association.emit_hash(
              association,
              read_expr.call(association.source),
              config.hash_output_key_type,
              config,
              field_index.fetch(GeneratedNames.filter_key(association)),
              builder
            )
          end
          descriptor.method_attributes.each do |method_attribute|
            FieldEmitters::MethodAttribute.emit_hash(
              method_attribute, config.hash_output_key_type,
              field_index.fetch(GeneratedNames.filter_key(method_attribute)), builder
            )
          end
          builder.line "result"
        end

        # Prepends per-record +@object+ / +@context+ / +@scope+ ivar
        # writes at the top of +_write_one+ / +_to_hash+ when
        # +descriptor.parent_class+ is non-+nil+ AND the Descriptor
        # declares a Symbol-body Method Attribute — the S18.3 wire-up
        # that lets the user-defined method read those ivars naturally
        # on +self+.
        #
        # Gated on a Symbol-body being present (revisiting the original
        # S18.3 decision to emit unconditionally on the +parent_class+
        # axis): a Symbol-body method is the only code that runs on the
        # Generated Class instance during a serialize — Callable bodies
        # and +if:+ guards receive +(record, context, scope)+ as explicit
        # args — so on descriptors without one the writes are pure
        # per-record overhead, which the merged-Panko GameSerializer
        # profile showed compounding across nested Composition.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_parent_class_ivar_writes(descriptor, builder)
          return if descriptor.parent_class.nil?
          return if descriptor.method_attributes.none? { |method_attribute| method_attribute.body.is_a?(Symbol) }
          builder.line "@object = record"
          builder.line "@context = context"
          builder.line "@scope = scope"
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
        # @param config [Panko::CodeGen::Config] resolved settings
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
