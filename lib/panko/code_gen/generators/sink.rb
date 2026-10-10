# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    class Sink
      # The child's +FIELD_INDEX+ is read through its class name when the method runs, so
      # self-recursive Descriptors resolve it.
      def child_filter_expr(association)
        "filters.child(:#{GeneratedNames.filter_key(association)}, " \
          "#{GeneratedNames.class_name(association.descriptor, suffix)}::#{GeneratedNames.field_index_const})"
      end

      # +case+/+when+, not an +if+/+elsif+ chain of +instance_of?+: under YJIT the chain gets
      # slower once the call site has warmed on one class. HashSink uses the +case+ as an expression.
      def child_write(association, record_expr, builder, &call_for)
        base_call = call_for.call(GeneratedNames.serializer_ivar(association))
        if association.variants.empty?
          builder.line base_call
          return
        end
        builder.line "case #{record_expr}"
        subclass_first(association.variants).each do |variant, index|
          model = "::#{variant.model.name}"
          builder.line "when #{model}"
          builder.indent do
            builder.line "if #{record_expr}.instance_of?(#{model})"
            builder.indent { builder.line call_for.call(GeneratedNames.variant_serializer_ivar(association, index)) }
            builder.line "else"
            builder.indent { builder.line base_call }
            builder.line "end"
          end
        end
        builder.line "else"
        builder.indent { builder.line base_call }
        builder.line "end"
      end

      # Each subclass before its ancestors, so a parent's +when+ arm does not take a declared
      # subclass.
      def subclass_first(variants)
        variants.each_with_index.sort_by { |variant, index| [-variant.model.ancestors.size, index] }
      end

      # The guard wraps the Source read too, so a falsy +if:+ skips the read.
      def with_if_guard(association, builder)
        if association.if
          builder.line "if #{if_guard_call_expression(GeneratedNames.if_guard_ivar(association), association.if.arity)}"
          builder.indent { yield }
          builder.line "end"
        else
          yield
        end
      end

      # The +callable_arity+ rule limits arity to +0..3+, so +else+ is arity 3.
      def if_guard_call_expression(ivar, arity)
        case arity
        when 0 then "#{ivar}.call"
        when 1 then "#{ivar}.call(record)"
        when 2 then "#{ivar}.call(record, context)"
        else "#{ivar}.call(record, context, scope)"
        end
      end

      # Symbol bodies need the explicit +self.+: a bare name such as +record+ or +value+ would
      # resolve to a local of the generated method.
      def method_attribute_call_expression(method_attribute)
        body = method_attribute.body
        return "self.#{body}" if body.is_a?(Symbol)
        ivar = GeneratedNames.callable_ivar(method_attribute)
        case body.arity
        when 0 then "#{ivar}.call"
        when 1 then "#{ivar}.call(record)"
        when 2 then "#{ivar}.call(record, context)"
        else "#{ivar}.call(record, context, scope)"
        end
      end
    end
  end
end
