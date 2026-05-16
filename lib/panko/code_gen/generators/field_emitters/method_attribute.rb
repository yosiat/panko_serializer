# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    module FieldEmitters
      # Emits the per-mode write for one +MethodAttribute+ inside a
      # +_write_one_*+ / +_to_hash_*+ helper. Two axes of variation:
      #
      # - *Output Mode* — JSON emits +writer.push_value(value, "<name>")+
      #   (the 2-arg form collapses +push_key+ + +push_value+ into one
      #   C-extension dispatch — byte-identical output, fewer dispatches);
      #   Hash emits +result[<key>] = value+. One module, one entry per mode,
      #   per +docs/output-modes.md § Composition across modes+.
      # - *Callable arity* — the call expression is specialized per arity
      #   per +docs/descriptor.md § Callable arity+. Arity is read off the
      #   Callable at +Compile+ time (the +callable_arity+ validator from
      #   S4.1, widened in S17.1 to +0..3+, has already pre-checked it
      #   lies in +{0, 1, 2, 3}+, so no validation here):
      #   * +0+: +@cb_<name>.call+
      #   * +1+: +@cb_<name>.call(record)+
      #   * +2+: +@cb_<name>.call(record, context)+
      #   * +3+: +@cb_<name>.call(record, context, scope)+
      #   No splat, no shared helper, no wrapper — the emitted Ruby reads
      #   exactly as one of the four call forms above per
      #   +docs/code-generation.md § Callable hoisting+.
      #
      # Both entries wrap the call in two nested guards:
      #
      # 1. +unless filters.drops?(<index>) ... end+ — the codegen-time
      #    Filter wrapper per +docs/filters.md § Threading through
      #    Composition+. A filter-dropped Method Attribute never invokes
      #    its Callable, so the Callable + +equal?(SKIP)+ pair is
      #    completely elided when the Filter says no.
      # 2. Inside it, +unless value.equal?(SerializersCodeGen::SKIP)+.
      #    The +equal?+ check is load-bearing — +==+ would let an
      #    +==+-overriding object accidentally collide with +SKIP+ per
      #    +docs/descriptor.md § SKIP sentinel+.
      module MethodAttribute
        # Emits the JSON-mode write for one +MethodAttribute+. Two
        # nested guards: outer +unless filters.drops?(<index>) ... end+
        # (filter-side); inner +unless value.equal?(SerializersCodeGen::SKIP)+
        # (SKIP-side, after the Callable runs). Inside the inner guard
        # one line: +writer.push_value(value, "<name>")+ — the 2-arg form
        # collapses the +push_key+ + +push_value+ pair into a single
        # C-extension dispatch (byte-identical output, fewer dispatches).
        #
        # @param method_attribute [SerializersCodeGen::MethodAttribute] the Field node
        # @param index [Integer] codegen-time +FIELD_INDEX+ position used
        #   in the +unless filters.drops?(<index>)+ wrapper
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(method_attribute, index, builder)
          builder.line "unless filters.drops?(#{index})"
          builder.indent do
            builder.line "value = #{call_expression(ivar_name(method_attribute), method_attribute.body.arity)}"
            builder.line "unless value.equal?(SerializersCodeGen::SKIP)"
            builder.indent do
              builder.line %(writer.push_value(value, "#{method_attribute.name}"))
            end
            builder.line "end"
          end
          builder.line "end"
        end

        # Emits the Hash-mode write for one +MethodAttribute+. Two
        # nested guards parallel to {.emit_json}: outer
        # +unless filters.drops?(<index>) ... end+; inner
        # +unless value.equal?(SerializersCodeGen::SKIP)+. Inside the
        # inner guard one line: +result[<key>] = value+. The output-key
        # shape comes from +output_key_type+ — +:string+ (default) emits
        # +result["<name>"]+, +:symbol+ emits +result[:<name>]+.
        #
        # @param method_attribute [SerializersCodeGen::MethodAttribute] the Field node
        # @param output_key_type [Symbol] +:string+ or +:symbol+ — the
        #   pre-validated value of +Config#hash_output_key_type+
        # @param index [Integer] codegen-time +FIELD_INDEX+ position used
        #   in the +unless filters.drops?(<index>)+ wrapper
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash(method_attribute, output_key_type, index, builder)
          key_lit = case output_key_type
          when :symbol then ":#{method_attribute.name}"
          else %("#{method_attribute.name}")
          end
          builder.line "unless filters.drops?(#{index})"
          builder.indent do
            builder.line "value = #{call_expression(ivar_name(method_attribute), method_attribute.body.arity)}"
            builder.line "unless value.equal?(SerializersCodeGen::SKIP)"
            builder.indent do
              builder.line "result[#{key_lit}] = value"
            end
            builder.line "end"
          end
          builder.line "end"
        end

        # Returns the arity-specialized call expression for one ivar. Pre-
        # validated by the +callable_arity+ rule (S4.1, widened to +0..3+
        # in S17.1) — only +0+, +1+, +2+, +3+ ever reach this method.
        # Specialization is per +docs/descriptor.md § Callable arity+ —
        # no splat / +*args+ / shared helper. Arity 3 threads +scope+
        # positionally as the third argument; arity 2 keeps its
        # +(record, context)+ meaning (no +scope+ leak).
        #
        # @param ivar_name [String] the +@cb_<name>+ ivar to invoke
        # @param arity [Integer] +0+, +1+, +2+, or +3+
        # @return [String] Ruby source like +"@cb_full_title.call(record, context)"+
        def self.call_expression(ivar_name, arity)
          case arity
          when 0 then "#{ivar_name}.call"
          when 1 then "#{ivar_name}.call(record)"
          when 2 then "#{ivar_name}.call(record, context)"
          else "#{ivar_name}.call(record, context, scope)"
          end
        end

        # Returns the per-Method-Attribute ivar name used for both
        # constructor hoisting and call-site invocation. Pinned at one
        # place so the constructor and the field emitter can't drift.
        #
        # @param method_attribute [SerializersCodeGen::MethodAttribute] the Field node
        # @return [String] the ivar token, e.g. +"@cb_full_title"+
        def self.ivar_name(method_attribute)
          "@cb_#{method_attribute.name}"
        end
      end
    end
  end
end
