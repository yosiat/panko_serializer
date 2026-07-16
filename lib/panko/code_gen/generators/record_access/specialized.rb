# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    module RecordAccess
      # Specialized-path Record-access emitter — used when a Descriptor's
      # +Model+ is set. Emits a single per-record entry with no
      # +is_a?(Hash)+ dispatch: the +Model+ contract assumes Records are
      # instances of the declared class, so every per-Attribute access
      # form is monomorphic at emit time.
      #
      # Per Attribute, the access form is chosen by the 3-step rule from
      # +AccessClassifier+:
      # - +:column+ → +record._read_attribute("name")+ — only when the
      #   reader is AR's own auto-generated one; a user-defined override
      #   is honored via method dispatch, so a specialized body stays
      #   observably identical to the Generic path.
      # - +:method+ → +record.name+ — instance methods that aren't
      #   columns, and user-overridden column readers.
      #
      # Association Sources stay on method dispatch (they name AR
      # relations, not columns); Method Attributes are independent of the
      # access strategy entirely. A non-AR class in +model:+ (+Struct+,
      # +Class.new+) falls through to method dispatch on every Attribute.
      #
      # The per-mode column fast paths (JSON wire-format columns,
      # raw-splice datetimes, Hash-mode cast elision) live on the sinks'
      # +specialized_attribute+ — this module owns the walk shape and the
      # classification predicates the sinks consult.
      module Specialized
        # Emits the per-record entry (plus, under +Config#guarded_model+,
        # the generic twin) under +builder+. The field walk is the same
        # {FieldWalk} the Generic path uses — only the per-Attribute emit
        # is overridden with the sink's classified form.
        #
        # @param descriptor [Panko::CodeGen::Descriptor] +#model+ must be
        #   non-+nil+ (caller already gated)
        # @param config [Panko::CodeGen::Config]
        # @param field_index [Hash{Symbol => Integer}] codegen-time
        #   +filter key → integer index+ map
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @param sink [Panko::CodeGen::Generators::Sink] the Output Mode
        #   adapter
        # @return [void]
        def self.emit(descriptor, config, field_index, builder, sink)
          ar_model = ar_model(descriptor)
          builder.line "def #{sink.entry_name}(#{sink.entry_params})"
          builder.indent do
            emit_model_guard(descriptor, config, "#{sink.generic_entry_name}(#{sink.entry_params})", builder)
            Generic.emit_parent_class_ivar_writes(descriptor, builder)
            FieldWalk.emit_fields(
              descriptor, config, field_index, builder, sink,
              read_expr: ->(source) { "record.#{source}" },
              attribute_emit: ->(attribute, index) { sink.specialized_attribute(attribute, ar_model, config, index, builder) }
            )
          end
          builder.line "end"
          emit_generic_twin(config, builder) do
            Generic.emit(descriptor, config, field_index, builder, sink, method_name: sink.generic_entry_name)
          end
        end

        # Emits the per-record class guard at the top of the entry when
        # +Config#guarded_model+ is set — the auto-specialization shape,
        # where no caller contract guarantees record homogeneity. A
        # mismatched record (Hash, PORO, STI sibling, heterogeneous array
        # element) delegates to the inline generic twin, so a variant
        # compiled for one record class can never emit wrong output for
        # another. For homogeneous data the guard is a single
        # perfectly-predicted +instance_of?+ per record.
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @param config [Panko::CodeGen::Config]
        # @param fallback_call [String] the twin invocation behind the guard
        # @param builder [Panko::CodeGen::CodeBuilder]
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

        # Emits the generic twin body after the guarded Specialized entry
        # — the same Fields through the Generic path's duck-typed reads
        # and Hash branch, sharing the instance's child serializers.
        # Emitted only under +Config#guarded_model+.
        #
        # @param config [Panko::CodeGen::Config]
        # @param builder [Panko::CodeGen::CodeBuilder]
        # @return [void]
        def self.emit_generic_twin(config, builder)
          return unless config.guarded_model
          builder.blank
          yield
        end

        # The read expression for one Attribute: +:column+ verdicts emit
        # +record._read_attribute("name")+; method verdicts (including
        # user-overridden column readers, honored, never bypassed) emit
        # +record.<name>+. +nil+ +ar_model+ falls back to method dispatch.
        #
        # @param attribute [Panko::CodeGen::Attribute]
        # @param ar_model [Class, nil]
        # @return [String]
        def self.attribute_read_expr(attribute, ar_model)
          return "record.#{attribute.source}" if ar_model.nil?
          case ActiveRecord::AccessClassifier.classify(ar_model, attribute.source)
          when :column then %(record._read_attribute("#{attribute.source}"))
          else "record.#{attribute.source}"
          end
        end

        # Returns +descriptor.model+ when it quacks like AR (responds to
        # +#columns_hash+ and +#attribute_methods_generated?+), +nil+
        # otherwise — and, on the AR path, calls
        # +DefineAttributeMethods.ensure!+ so AR's lazy column readers
        # are populated before classification (idempotent; the
        # +SourceResolution+ validator already invoked it, so this is the
        # warm-path short-circuit that keeps the Generator runnable
        # without the validator in test affordances).
        #
        # @param descriptor [Panko::CodeGen::Descriptor]
        # @return [Class, nil]
        def self.ar_model(descriptor)
          model = descriptor.model
          return nil unless model.respond_to?(:columns_hash) && model.respond_to?(:attribute_methods_generated?)
          ActiveRecord::DefineAttributeMethods.ensure!(model)
          model
        end

        # Whether +attribute+ is JSON-typed on the Model AND carries a
        # +:column+ verdict — the +:wire_format+ JSON-mode fast path. The
        # classify gate mirrors {datetime_column_attribute?}: a
        # user-overridden reader must keep method dispatch (both column
        # emits read past the override).
        #
        # @param attribute [Panko::CodeGen::Attribute]
        # @param ar_model [Class, nil]
        # @return [Boolean]
        def self.json_column_attribute?(attribute, ar_model)
          return false if ar_model.nil?
          return false unless ActiveRecord::AccessClassifier.json_typed?(ar_model, attribute.source)
          ActiveRecord::AccessClassifier.classify(ar_model, attribute.source) == :column
        end

        # Whether +attribute+ takes the raw-string datetime fast path:
        # datetime-typed, a +:column+ verdict, and — checked at compile
        # time — +::ActiveRecord.default_timezone == :utc+, since the raw
        # DB bytes carry no zone and only under +:utc+ is the spliced
        # trailing "Z" truthful. The +::+ matters: bare +ActiveRecord+
        # here resolves to +Panko::CodeGen::ActiveRecord+.
        #
        # @param attribute [Panko::CodeGen::Attribute]
        # @param ar_model [Class, nil]
        # @return [Boolean]
        def self.datetime_column_attribute?(attribute, ar_model)
          return false if ar_model.nil?
          return false unless ::ActiveRecord.default_timezone == :utc
          return false unless ActiveRecord::AccessClassifier.datetime_typed?(ar_model, attribute.source)
          ActiveRecord::AccessClassifier.classify(ar_model, attribute.source) == :column
        end

        # Whether +attribute+ is a +:column+ verdict whose type is
        # provably non-datetime — the Hash-mode emit may then skip the
        # per-value +cast_datetime+ wrapper.
        #
        # @param attribute [Panko::CodeGen::Attribute]
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
