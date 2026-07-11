# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    module RecordAccess
      # Specialized-path Record-access emitter — used when a Descriptor's
      # +Model+ field is set per +docs/compilation.md § Specialized path+.
      # Emits a single +_write_one(record, writer, context, scope, filters)+
      # (JSON) or +_to_hash(record, context, scope, filters)+ (Hash) — no
      # +is_a?(Hash)+ dispatch and no +_write_one_hash+ / +_write_one_object+
      # split.
      #
      # When +descriptor.parent_class+ is non-+nil+ (S18.3), the single
      # body is prepended with three +@object = record; @context =
      # context; @scope = scope+ lines so a user-defined method on the
      # parent class can read those ivars on +self+ — the Panko-shape
      # contract from +docs/merging-into-panko.md § Generated Class
      # subclasses the user's Panko serializer+. See
      # {emit_parent_class_ivar_writes} for the rationale.
      # The +Model+ contract assumes Records are instances of the declared
      # class (or its subclasses), so every per-Attribute access form
      # is monomorphic at emit time.
      #
      # Per Attribute, the access form is chosen by the 3-step rule from
      # +AccessClassifier+ (S6.1):
      # - +:column+ → +record._read_attribute("name")+. The fastest access
      #   form on Ruby 4 + YJIT + AR 8.1; only taken when the reader is
      #   AR's own auto-generated one — a user-defined override is honored
      #   via method dispatch, so a specialized body stays observably
      #   identical to the Generic path.
      # - +:method+ → +record.name+. Standard method dispatch, used for
      #   instance methods that aren't columns and for user-overridden
      #   column readers.
      #
      # +Association+ Sources stay on +record.<source>+ method dispatch
      # — Associations name AR relations (or methods returning related
      # Records), not columns; +_read_attribute+ doesn't apply. +Method
      # Attributes+ are independent of the access strategy entirely (they
      # invoke a hoisted Callable, not the Record's reader).
      #
      # Non-AR class fallback: when +descriptor.model+ is a non-AR class
      # (no +#columns_hash+), every Attribute falls through to method
      # dispatch. This is the "+Struct+ or plain +Class.new+ in +models:+"
      # case from +docs/compilation.md § Non-AR class in +models++ — the
      # contract still binds (no Hash branch), just the column-form
      # optimization doesn't apply.
      #
      # +DefineAttributeMethods.ensure!+ is invoked on the AR Model at the
      # top of +emit_json+ / +emit_hash+ (inside {ar_model}) — before
      # classification — so AR's lazy column readers are populated in time
      # for step (2) of the 3-step rule. Idempotent across calls; the
      # +SourceResolution+ validator (S6.1) also calls +ensure!+, so the
      # warm path here is one short-circuit per class.
      module Specialized
        # Emits the JSON-mode +_write_one+ helper under +builder+. No
        # +_write_one_hash+ / +_write_one_object+ split — the Specialized
        # path's contract is "Records are instances of declared +models:+",
        # so the body is monomorphic end-to-end. Per-Field emit delegates
        # to +FieldEmitters::Attribute+ / +FieldEmitters::Association+ /
        # +FieldEmitters::MethodAttribute+ — same per-Field shape as the
        # Generic path; only the per-Attribute read expression differs.
        #
        # @param descriptor [Panko::CodeGen::Descriptor] the Descriptor
        #   being compiled; +#models+ must be non-+nil+ (caller already
        #   gated)
        # @param config [Panko::CodeGen::Config] resolved compile-time
        #   settings; threaded through to per-Field emitters whose source
        #   choices depend on it (e.g. +Association#emit_json+ branches on
        #   +null_for_missing_has_one+)
        # @param field_index [Hash{Symbol => Integer}] codegen-time
        #   +Field name → integer index+ map per
        #   +docs/filters.md § Threading through Composition+; threaded
        #   into each +FieldEmitters::*.emit_*+ call so the emitted
        #   +unless filters.drops?(<integer>)+ wrapper bakes the
        #   per-Field literal at codegen time
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(descriptor, config, field_index, builder)
          ar_model = ar_model(descriptor)
          builder.line "def _write_one(record, writer, context, scope, filters)"
          builder.indent do
            emit_model_guard(descriptor, config, "_generic_write_one(record, writer, context, scope, filters)", builder)
            emit_parent_class_ivar_writes(descriptor, builder)
            builder.line "writer.push_object"
            descriptor.attributes.each do |attribute|
              if json_column_attribute?(attribute, ar_model)
                FieldEmitters::Attribute.emit_json_column(attribute, config, field_index.fetch(attribute.name), builder)
              elsif datetime_column_attribute?(attribute, ar_model)
                FieldEmitters::Attribute.emit_json_datetime_column(attribute, field_index.fetch(attribute.name), builder)
              else
                FieldEmitters::Attribute.emit_json(attribute, attribute_read_expr(attribute, ar_model), field_index.fetch(attribute.name), builder)
              end
            end
            descriptor.associations.each do |association|
              FieldEmitters::Association.emit_json(association, "record.#{association.source}", config, field_index.fetch(association.name), builder)
            end
            descriptor.method_attributes.each do |method_attribute|
              FieldEmitters::MethodAttribute.emit_json(method_attribute, field_index.fetch(method_attribute.name), builder)
            end
            builder.line "writer.pop"
          end
          builder.line "end"
          emit_generic_twin(config, builder) do
            Generic.emit_json(descriptor, config, field_index, builder, method_name: "_generic_write_one")
          end
        end

        # Emits the Hash-mode +_to_hash+ helper under +builder+, parallel
        # to +emit_json+. Body is +result = {}; ...; result+ per
        # +docs/output-modes.md § :hash+ — no Writer indirection. Output
        # keys come from +Config#hash_output_key_type+; per-Attribute
        # reads use the Specialized 3-step rule.
        #
        # @param descriptor [Panko::CodeGen::Descriptor] the Descriptor
        # @param config [Panko::CodeGen::Config] resolved settings
        # @param field_index [Hash{Symbol => Integer}] codegen-time
        #   +Field name → integer index+ map (mirror of {emit_json})
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash(descriptor, config, field_index, builder)
          ar_model = ar_model(descriptor)
          builder.line "def _to_hash(record, context, scope, filters)"
          builder.indent do
            emit_model_guard(descriptor, config, "_generic_to_hash(record, context, scope, filters)", builder)
            emit_parent_class_ivar_writes(descriptor, builder)
            builder.line "result = {}"
            descriptor.attributes.each do |attribute|
              if datetime_column_attribute?(attribute, ar_model)
                FieldEmitters::Attribute.emit_hash_datetime_column(
                  attribute, config.hash_output_key_type, field_index.fetch(attribute.name), builder
                )
              else
                FieldEmitters::Attribute.emit_hash(
                  attribute,
                  attribute_read_expr(attribute, ar_model),
                  config.hash_output_key_type,
                  field_index.fetch(attribute.name),
                  builder,
                  cast: !plain_column_attribute?(attribute, ar_model)
                )
              end
            end
            descriptor.associations.each do |association|
              FieldEmitters::Association.emit_hash(
                association,
                "record.#{association.source}",
                config.hash_output_key_type,
                config,
                field_index.fetch(association.name),
                builder
              )
            end
            descriptor.method_attributes.each do |method_attribute|
              FieldEmitters::MethodAttribute.emit_hash(method_attribute, config.hash_output_key_type, field_index.fetch(method_attribute.name), builder)
            end
            builder.line "result"
          end
          builder.line "end"
          emit_generic_twin(config, builder) do
            Generic.emit_hash(descriptor, config, field_index, builder, method_name: "_generic_to_hash")
          end
        end

        # Prepends per-record +@object+ / +@context+ / +@scope+ ivar
        # writes at the top of the single +_write_one+ (JSON) /
        # +_to_hash+ (Hash) body when +descriptor.parent_class+ is
        # non-+nil+ — the S18.3 wire-up that lets a user-defined +def+
        # on the parent class read +@object+ / +@context+ / +@scope+
        # naturally instead of taking an explicit +(record, context,
        # scope)+ tuple (the Panko-shape contract from
        # +docs/merging-into-panko.md § Generated Class subclasses the
        # user's Panko serializer+).
        #
        # No-op when +parent_class+ is +nil+ — the bare descriptor stays
        # byte-identical to pre-S18 emit so every existing snapshot
        # remains pinned. Additionally gated on a Symbol-body Method
        # Attribute being present (revisiting the original S18.3
        # decision to emit unconditionally on the +parent_class+ axis,
        # which bench-validated the writes as noise-level on the shapes
        # measured then): a Symbol-body method is the only code that
        # runs on the Generated Class instance during a serialize —
        # Callable bodies and +if:+ guards receive +(record, context,
        # scope)+ as explicit args — and the merged-Panko GameSerializer
        # profile showed the writes compounding across nested
        # Composition on descriptors that never read them.
        #
        # Deviation from the "GC ivars are init-time constants" pattern
        # in +docs/code-generation.md+ — documented at the field-emitter
        # +call_expression+ boundary; the full doc-page update lands in
        # S18.4.
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

        # Emits the per-record class guard at the top of +_write_one+ /
        # +_to_hash+ when +Config#guarded_model+ is set — the
        # auto-specialization shape, where no caller contract guarantees
        # record homogeneity. A mismatched record (Hash, PORO, STI
        # sibling, heterogeneous array element) delegates to the inline
        # generic twin via +fallback_call+, so a variant compiled for one
        # record class can never emit wrong output for another. For
        # homogeneous data the guard is a single perfectly-predicted
        # +instance_of?+ per record. No-op under the (unguarded)
        # declared-Model contract.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @param config [Panko::CodeGen::Config] resolved settings
        # @param fallback_call [String] the twin invocation to emit behind
        #   the guard
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        # @raise [Panko::CodeGen::CompileError] when guarded emission is
        #   requested for an anonymous Model — the guard references the
        #   Model by constant path, so it must be named
        def self.emit_model_guard(descriptor, config, fallback_call, builder)
          return unless config.guarded_model
          model_name = descriptor.model.name
          if model_name.nil?
            raise CompileError,
              "#{descriptor.name}: guarded_model requires a named Model class; got anonymous #{descriptor.model.inspect}"
          end
          builder.line "return #{fallback_call} unless record.instance_of?(::#{model_name})"
        end

        # Emits the generic twin body (+_generic_write_one+ /
        # +_generic_to_hash+) after the guarded Specialized entry — the
        # same Fields through the Generic path's duck-typed reads and
        # Hash branch, sharing the instance's child serializers and
        # Writer. Emitted only under +Config#guarded_model+; the block
        # supplies the mode-appropriate {Generic} emit.
        #
        # @param config [Panko::CodeGen::Config] resolved settings
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_generic_twin(config, builder)
          return unless config.guarded_model
          builder.blank
          yield
        end

        # Returns the read expression for one Attribute in the Specialized
        # path. Runs +AccessClassifier.classify+ against the AR Model;
        # +:column+ verdicts emit +record._read_attribute("name")+, method
        # verdicts (including user-overridden column readers, which are
        # honored, never bypassed) emit +record.<name>+. When +ar_model+
        # is +nil+ (the declared Model fails the AR duck-type test), falls
        # back to method dispatch for every Attribute — the "non-AR class
        # in +models:+" case from +docs/compilation.md § Non-AR class in
        # `models`+.
        #
        # @param attribute [Panko::CodeGen::Attribute]
        # @param ar_model [Class, nil]
        # @return [String] Ruby source like +'record._read_attribute("title")'+
        #   or +"record.headline"+
        def self.attribute_read_expr(attribute, ar_model)
          return "record.#{attribute.source}" if ar_model.nil?
          case ActiveRecord::AccessClassifier.classify(ar_model, attribute.source)
          when :column then %(record._read_attribute("#{attribute.source}"))
          else "record.#{attribute.source}"
          end
        end

        # Returns +descriptor.model+ when it quacks like AR, +nil+
        # otherwise — and, on the AR path, calls
        # +DefineAttributeMethods.ensure!+ so AR's lazy column readers are
        # populated before classification. +ensure!+ is idempotent — the
        # +SourceResolution+ validator already invoked it during the
        # pre-Generator validation pass, so this is the warm-path
        # short-circuit; calling it again here keeps the Generator
        # runnable without the validator in test affordances.
        #
        # The duck-type mirrors +Validators::SourceResolution+'s gate: a
        # class qualifies as AR-like when it responds to both
        # +#columns_hash+ (the column table the classifier introspects)
        # and +#attribute_methods_generated?+ (the gate +ensure!+
        # short-circuits on). A non-AR Model (+Struct+, +Class.new+)
        # returns +nil+ and every Attribute falls through to method
        # dispatch.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @return [Class, nil]
        def self.ar_model(descriptor)
          model = descriptor.model
          return nil unless model.respond_to?(:columns_hash) && model.respond_to?(:attribute_methods_generated?)
          ActiveRecord::DefineAttributeMethods.ensure!(model)
          model
        end

        # Returns +true+ when +attribute+ is JSON-typed on the AR Model —
        # the S12.5 +:wire_format+ JSON-mode emit path. +nil+ +ar_model+
        # (the "non-AR class in models:" case) returns +false+; that path
        # falls through to method dispatch on every Attribute and is
        # irrelevant to the JSON-column optimization.
        #
        # @param attribute [Panko::CodeGen::Attribute] the Field node
        # @param ar_model [Class, nil]
        # @return [Boolean]
        def self.json_column_attribute?(attribute, ar_model)
          return false if ar_model.nil?
          ActiveRecord::AccessClassifier.json_typed?(ar_model, attribute.source)
        end

        # Returns +true+ when +attribute+ takes the raw-string datetime fast
        # path: datetime-typed on the Model, a +:column+ verdict from the
        # classifier (a user override must keep method dispatch), and —
        # checked at compile time — +::ActiveRecord.default_timezone ==
        # :utc+, since the raw DB bytes carry no zone and only under +:utc+
        # is the spliced trailing "Z" truthful. The +::+ matters: bare
        # +ActiveRecord+ here resolves to +Panko::CodeGen::ActiveRecord+.
        #
        # @param attribute [Panko::CodeGen::Attribute] the Field node
        # @param ar_model [Class, nil]
        # @return [Boolean]
        def self.datetime_column_attribute?(attribute, ar_model)
          return false if ar_model.nil?
          return false unless ::ActiveRecord.default_timezone == :utc
          return false unless ActiveRecord::AccessClassifier.datetime_typed?(ar_model, attribute.source)
          ActiveRecord::AccessClassifier.classify(ar_model, attribute.source) == :column
        end

        # Returns +true+ when +attribute+ is a +:column+ verdict whose type
        # is provably non-datetime on the Model — the Hash-mode emit may
        # then skip the per-value +cast_datetime+ wrapper.
        #
        # @param attribute [Panko::CodeGen::Attribute] the Field node
        # @param ar_model [Class, nil]
        # @return [Boolean]
        def self.plain_column_attribute?(attribute, ar_model)
          return false if ar_model.nil?
          return false unless ActiveRecord::AccessClassifier.plain_typed?(ar_model, attribute.source)
          ActiveRecord::AccessClassifier.classify(ar_model, attribute.source) == :column
        end
      end
    end
  end
end
