# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    module RecordAccess
      # Records are assumed to be instances of the Descriptor's Model, so there is no Hash branch.
      module Specialized
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

        # Under auto-specialization nothing promises every record has the Model's class, so a record of
        # another class (Hash, STI sibling, mixed array) goes to the generic twin instead of wrong output.
        def self.emit_model_guard(descriptor, config, fallback_call, builder)
          return unless config.guarded_model
          model_name = descriptor.model.name
          if model_name.nil?
            raise CompileError,
              "#{descriptor.name}: guarded_model requires a named Model class; got anonymous #{descriptor.model.inspect}"
          end
          builder.line "return #{fallback_call} unless record.instance_of?(::#{model_name})"
        end

        def self.emit_generic_twin(config, builder)
          return unless config.guarded_model
          builder.blank
          yield
        end

        # A method the Model does not declare as an attribute reads the loaded attribute first, so a
        # SELECT alias named like a method (+thing_ids+ next to +has_many :things+) returns the selected value.
        def self.attribute_read_expr(attribute, ar_model)
          source = attribute.source
          return "record.#{source}" if ar_model.nil?
          return %(record._read_attribute("#{source}")) if ActiveRecord::AccessClassifier.classify(ar_model, source) == :column
          return "record.#{source}" if declared_attribute?(ar_model, source)
          %((record._has_attribute?("#{source}") ? record._read_attribute("#{source}") : record.#{source}))
        end

        def self.declared_attribute?(ar_model, source)
          ar_model.attribute_types.key?(source.to_s) || ar_model.attribute_aliases.key?(source.to_s)
        end

        # Called here too so the Generator works without the validators; repeating +ensure!+ is safe.
        def self.ar_model(descriptor)
          model = descriptor.model
          return nil unless model.respond_to?(:columns_hash) && model.respond_to?(:attribute_methods_generated?)
          ActiveRecord::DefineAttributeMethods.ensure!(model)
          model
        end

        # Requires a +:column+ result because the column fast paths read past a user-overridden reader.
        def self.json_column_attribute?(attribute, ar_model)
          return false if ar_model.nil?
          return false unless ActiveRecord::AccessClassifier.json_typed?(ar_model, attribute.source)
          ActiveRecord::AccessClassifier.classify(ar_model, attribute.source) == :column
        end

        # Only under +:utc+ is the zoneless raw DB string really UTC, so the fast path's trailing "Z" is true.
        # The +::+ matters: bare +ActiveRecord+ here resolves to +Panko::CodeGen::ActiveRecord+.
        def self.datetime_column_attribute?(attribute, ar_model)
          return false if ar_model.nil?
          return false unless ::ActiveRecord.default_timezone == :utc
          return false unless ActiveRecord::AccessClassifier.datetime_typed?(ar_model, attribute.source)
          ActiveRecord::AccessClassifier.classify(ar_model, attribute.source) == :column
        end

        def self.plain_column_attribute?(attribute, ar_model)
          return false if ar_model.nil?
          return false unless ActiveRecord::AccessClassifier.plain_typed?(ar_model, attribute.source)
          ActiveRecord::AccessClassifier.classify(ar_model, attribute.source) == :column
        end
      end
    end
  end
end
