# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # The Output Mode seam. One descriptor-walking emitter ({ClassEmitter}
    # + {FieldWalk} + the {RecordAccess} strategies) talks to this
    # interface; {JsonSink} and {HashSink} are the two adapters that
    # satisfy it. Everything mode-divergent — leaf write shapes, record
    # frames, entry signatures, per-class constants — lives behind it, so
    # a value-cast or emit-shape fix lands in one adapter instead of
    # drifting across parallel per-mode trees.
    #
    # Adapters are stateless; one frozen instance per mode is shared via
    # {Panko::CodeGen::Generator.sink_for}.
    class Sink
      # Ruby source for one Association's +filters.child(...)+ call. The
      # descent key ties to the same +GeneratedNames.filter_key+ the
      # child's +FIELD_INDEX+ is built from, so filter addressing can't
      # drift between levels. The child's +FIELD_INDEX+ is referenced by
      # its fully qualified constant — a single +get_const+ on a literal
      # token, and self-recursive Descriptors resolve it because constant
      # lookup happens at method-execution time, when the class is fully
      # defined.
      #
      # @param association [Panko::CodeGen::Association]
      # @return [String]
      def child_filter_expr(association)
        "filters.child(:#{GeneratedNames.filter_key(association)}, " \
          "#{GeneratedNames.class_name(association.descriptor, suffix)}::#{GeneratedNames.field_index_const})"
      end

      # Wraps +block+ in +if @cb_if_<name>.call(...) ... end+ when the
      # Association carries an +if:+ Callable. The wrap pre-empts the
      # per-Kind body — Source read, key push, nested call — so a falsy
      # guard short-circuits before any of them run (the Filter > +if:+ >
      # Source precedence ladder).
      #
      # @param association [Panko::CodeGen::Association]
      # @param builder [Panko::CodeGen::CodeBuilder]
      # @yield emits the per-Kind body inside the guard
      # @return [void]
      def with_if_guard(association, builder)
        if association.if
          builder.line "if #{if_guard_call_expression(GeneratedNames.if_guard_ivar(association), association.if.arity)}"
          builder.indent { yield }
          builder.line "end"
        else
          yield
        end
      end

      # The arity-specialized invocation for an +if:+-guard ivar. Arity
      # is pre-validated to +0..3+ by the +callable_arity+ rule; arity 3
      # threads +scope+ positionally, arity 2 keeps +(record, context)+.
      #
      # @param ivar [String] the +@cb_if_<name>+ ivar to invoke
      # @param arity [Integer] +0+, +1+, +2+, or +3+
      # @return [String]
      def if_guard_call_expression(ivar, arity)
        case arity
        when 0 then "#{ivar}.call"
        when 1 then "#{ivar}.call(record)"
        when 2 then "#{ivar}.call(record, context)"
        else "#{ivar}.call(record, context, scope)"
        end
      end

      # The body-kind-specialized invocation for one Method Attribute.
      # Symbol bodies emit +self.<method_name>+ — the explicit receiver is
      # load-bearing: the emitted bodies have +record+ / +writer+ /
      # +context+ / +scope+ / +filters+ / +value+ / +result+ locals in
      # scope, and a bare token for a user method with any of those names
      # would silently resolve to the local. Callable bodies emit the
      # arity-specialized +@cb_<name>.call(...)+.
      #
      # @param method_attribute [Panko::CodeGen::MethodAttribute]
      # @return [String]
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
