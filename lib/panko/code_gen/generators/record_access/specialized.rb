# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    module RecordAccess
      # Specialized-path Record-access emitter — used when a Descriptor's
      # +Models+ field is set per +docs/compilation.md § Specialized path+.
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
      # The +Models+ contract assumes Records are instances of the declared
      # classes (or their subclasses), so every per-Attribute access form
      # is monomorphic at emit time.
      #
      # Per Attribute, the access form is chosen by the 3-step rule from
      # +AccessClassifier+ (S6.1):
      # - +:column+ → +record._read_attribute("name")+. The fastest access
      #   form on Ruby 4 + YJIT + AR 8.1; bypasses any user-defined reader
      #   override per +docs/compilation.md § Overrides are bypassed+.
      # - +:method+ → +record.name+. Standard method dispatch, used for
      #   instance methods that aren't columns.
      #
      # +Association+ Sources stay on +record.<source>+ method dispatch
      # — Associations name AR relations (or methods returning related
      # Records), not columns; +_read_attribute+ doesn't apply. +Method
      # Attributes+ are independent of the access strategy entirely (they
      # invoke a hoisted Callable, not the Record's reader).
      #
      # Non-AR class fallback: when +descriptor.models+ contains only
      # non-AR classes (no +#columns_hash+), every Attribute falls through
      # to method dispatch. This is the "+Struct+ or plain +Class.new+ in
      # +models:+" case from +docs/compilation.md § Non-AR class in
      # +models++ — the contract still binds (no Hash branch), just the
      # column-form optimization doesn't apply.
      #
      # +DefineAttributeMethods.ensure!+ is invoked on every AR class in
      # +descriptor.models+ at the top of +emit_json+ / +emit_hash+ —
      # before classification — so AR's lazy column readers are populated
      # in time for step (2) of the 3-step rule. Idempotent across calls;
      # the +SourceResolution+ validator (S6.1) also calls +ensure!+, so
      # the warm path here is one short-circuit per class.
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
          ensure_attribute_methods!(descriptor)
          ar_classes = descriptor.models.select { |m| ar_class?(m) }
          builder.line "def _write_one(record, writer, context, scope, filters)"
          builder.indent do
            emit_parent_class_ivar_writes(descriptor, builder)
            builder.line "writer.push_object"
            descriptor.attributes.each do |attribute|
              if json_column_attribute?(attribute, ar_classes)
                FieldEmitters::Attribute.emit_json_column(attribute, config, field_index.fetch(attribute.name), builder)
              elsif datetime_column_attribute?(attribute, ar_classes)
                FieldEmitters::Attribute.emit_json_datetime_column(attribute, field_index.fetch(attribute.name), builder)
              else
                FieldEmitters::Attribute.emit_json(attribute, attribute_read_expr(attribute, descriptor), field_index.fetch(attribute.name), builder)
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
          ensure_attribute_methods!(descriptor)
          ar_classes = descriptor.models.select { |m| ar_class?(m) }
          builder.line "def _to_hash(record, context, scope, filters)"
          builder.indent do
            emit_parent_class_ivar_writes(descriptor, builder)
            builder.line "result = {}"
            descriptor.attributes.each do |attribute|
              if datetime_column_attribute?(attribute, ar_classes)
                FieldEmitters::Attribute.emit_hash_datetime_column(
                  attribute, config.hash_output_key_type, field_index.fetch(attribute.name), builder
                )
              else
                FieldEmitters::Attribute.emit_hash(
                  attribute,
                  attribute_read_expr(attribute, descriptor),
                  config.hash_output_key_type,
                  field_index.fetch(attribute.name),
                  builder,
                  cast: !plain_column_attribute?(attribute, ar_classes)
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

        # Returns the read expression for one Attribute in the Specialized
        # path. Filters +descriptor.models+ to the AR-class subset and
        # runs +AccessClassifier.classify+ against it as a whole; the
        # classifier applies the intersection rule per +docs/compilation.md
        # § STI and mixed class sets+ (column-in-all → +:column+;
        # method-in-all → +:method+; else raise). Column-backed verdicts
        # emit +record._read_attribute("name")+; method verdicts emit
        # +record.<name>+. When the AR subset is empty (every class
        # in +descriptor.models+ fails the duck-type test), falls back
        # to method dispatch for every Attribute — the "non-AR class in
        # +models:+" case from +docs/compilation.md § Non-AR class in
        # `models`+.
        #
        # @param attribute [Panko::CodeGen::Attribute]
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @return [String] Ruby source like +'record._read_attribute("title")'+
        #   or +"record.headline"+
        def self.attribute_read_expr(attribute, descriptor)
          ar_classes = descriptor.models.select { |m| ar_class?(m) }
          return "record.#{attribute.source}" if ar_classes.empty?
          case ActiveRecord::AccessClassifier.classify(ar_classes, attribute.source)
          when :column then %(record._read_attribute("#{attribute.source}"))
          else "record.#{attribute.source}"
          end
        end

        # Calls +DefineAttributeMethods.ensure!+ on every AR class in
        # +descriptor.models+ so AR's lazy column readers are populated
        # before classification. Idempotent — the +SourceResolution+
        # validator already invoked +ensure!+ during the pre-Generator
        # validation pass, so this is the warm-path short-circuit. Calling
        # again here keeps the Generator runnable without the validator
        # in test affordances and pins the acceptance criterion's
        # "Generator calls +DefineAttributeMethods.ensure!+ ... before any
        # classification".
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @return [void]
        def self.ensure_attribute_methods!(descriptor)
          descriptor.models.each do |klass|
            next unless ar_class?(klass)
            ActiveRecord::DefineAttributeMethods.ensure!(klass)
          end
        end

        # Duck-typed AR test mirroring +Validators::SourceResolution+'s
        # gate. A class qualifies as AR-like when it responds to both
        # +#columns_hash+ (the column-table the classifier introspects)
        # and +#attribute_methods_generated?+ (the gate +ensure!+
        # short-circuits on). Non-AR classes (+Struct+, +Class.new+) fail
        # this test and are skipped in both helpers, falling through to
        # method dispatch.
        #
        # @param klass [Class]
        # @return [Boolean]
        def self.ar_class?(klass)
          klass.respond_to?(:columns_hash) && klass.respond_to?(:attribute_methods_generated?)
        end

        # Returns +true+ when +attribute+ is JSON-typed on every AR class in
        # +ar_classes+. The S12.5 +:wire_format+ JSON-mode emit path fires
        # only when the type is uniformly JSON across the whole +Models+ set
        # — a non-uniform set (one class with +t.json+ and a sibling with
        # +t.string+) downgrades to today's +emit_json+ shape so the
        # Specialized class stays monomorphic per Attribute. Empty
        # +ar_classes+ (the "non-AR class in models:" case) returns +false+;
        # that path falls through to method dispatch on every Attribute and
        # is irrelevant to the JSON-column optimization.
        #
        # @param attribute [Panko::CodeGen::Attribute] the Field node
        # @param ar_classes [Array<Class>] AR-class subset of
        #   +descriptor.models+
        # @return [Boolean]
        def self.json_column_attribute?(attribute, ar_classes)
          return false if ar_classes.empty?
          ar_classes.all? { |klass| ActiveRecord::AccessClassifier.json_typed?(klass, attribute.source) }
        end

        # Returns +true+ when +attribute+ takes the raw-string datetime fast
        # path: uniformly datetime-typed across the whole +Models+ set, a
        # +:column+ verdict from the classifier (a user override must keep
        # method dispatch), and — checked at compile time —
        # +::ActiveRecord.default_timezone == :utc+, since the raw DB bytes
        # carry no zone and only under +:utc+ is the spliced trailing "Z"
        # truthful. The +::+ matters: bare +ActiveRecord+ here resolves to
        # +Panko::CodeGen::ActiveRecord+.
        #
        # @param attribute [Panko::CodeGen::Attribute] the Field node
        # @param ar_classes [Array<Class>] AR-class subset of
        #   +descriptor.models+
        # @return [Boolean]
        def self.datetime_column_attribute?(attribute, ar_classes)
          return false if ar_classes.empty?
          return false unless ::ActiveRecord.default_timezone == :utc
          return false unless ar_classes.all? { |klass| ActiveRecord::AccessClassifier.datetime_typed?(klass, attribute.source) }
          ActiveRecord::AccessClassifier.classify(ar_classes, attribute.source) == :column
        end

        # Returns +true+ when +attribute+ is a +:column+ verdict whose type
        # is provably non-datetime on every class in the +Models+ set — the
        # Hash-mode emit may then skip the per-value +cast_datetime+ wrapper.
        #
        # @param attribute [Panko::CodeGen::Attribute] the Field node
        # @param ar_classes [Array<Class>] AR-class subset of
        #   +descriptor.models+
        # @return [Boolean]
        def self.plain_column_attribute?(attribute, ar_classes)
          return false if ar_classes.empty?
          return false unless ar_classes.all? { |klass| ActiveRecord::AccessClassifier.plain_typed?(klass, attribute.source) }
          ActiveRecord::AccessClassifier.classify(ar_classes, attribute.source) == :column
        end
      end
    end
  end
end
