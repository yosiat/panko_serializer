# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    module RecordAccess
      # Specialized-path Record-access emitter — used when a Descriptor's
      # +Models+ field is set per +docs/compilation.md § Specialized path+.
      # Emits a single +_write_one(record, writer, context, filters)+ (JSON)
      # or +_to_hash(record, context, filters)+ (Hash) — no +is_a?(Hash)+
      # dispatch and no +_write_one_hash+ / +_write_one_object+ split.
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
        # @param descriptor [SerializersCodeGen::Descriptor] the Descriptor
        #   being compiled; +#models+ must be non-+nil+ (caller already
        #   gated)
        # @param config [SerializersCodeGen::Config] resolved compile-time
        #   settings; threaded through to per-Field emitters whose source
        #   choices depend on it (e.g. +Association#emit_json+ branches on
        #   +null_for_missing_has_one+)
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(descriptor, config, builder)
          ensure_attribute_methods!(descriptor)
          builder.line "def _write_one(record, writer, context, filters)"
          builder.indent do
            builder.line "writer.push_object"
            descriptor.attributes.each do |attribute|
              FieldEmitters::Attribute.emit_json(attribute, attribute_read_expr(attribute, descriptor), builder)
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

        # Emits the Hash-mode +_to_hash+ helper under +builder+, parallel
        # to +emit_json+. Body is +result = {}; ...; result+ per
        # +docs/output-modes.md § :hash+ — no Writer indirection. Output
        # keys come from +Config#hash_output_key_type+; per-Attribute
        # reads use the Specialized 3-step rule.
        #
        # @param descriptor [SerializersCodeGen::Descriptor] the Descriptor
        # @param config [SerializersCodeGen::Config] resolved settings
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash(descriptor, config, builder)
          ensure_attribute_methods!(descriptor)
          builder.line "def _to_hash(record, context, filters)"
          builder.indent do
            builder.line "result = {}"
            descriptor.attributes.each do |attribute|
              FieldEmitters::Attribute.emit_hash(
                attribute,
                attribute_read_expr(attribute, descriptor),
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
        # @param attribute [SerializersCodeGen::Attribute]
        # @param descriptor [SerializersCodeGen::Descriptor]
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
        # @param descriptor [SerializersCodeGen::Descriptor]
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
      end
    end
  end
end
