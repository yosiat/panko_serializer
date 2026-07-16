# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    module FieldEmitters
      # Emits the per-mode write for one +MethodAttribute+ inside a
      # +_write_one_*+ / +_to_hash_*+ helper. Three axes of variation:
      #
      # - *Output Mode* — JSON emits +writer.push_value(value, "<name>")+
      #   (the 2-arg form collapses +push_key+ + +push_value+ into one
      #   C-extension dispatch — byte-identical output, fewer dispatches);
      #   Hash emits +result[<key>] = value+. One module, one entry per mode,
      #   per +docs/code_gen/output-modes.md § Composition across modes+.
      # - *Body kind* — the call expression branches on
      #   +method_attribute.body.is_a?(Symbol)+ per S18.3 /
      #   +docs/code_gen/merging-into-panko.md § Generated Class subclasses the
      #   user's Panko serializer+:
      #   * Symbol → +value = self.<method_name>+ (explicit-receiver
      #     method dispatch on +self+, reachable because the owning
      #     Descriptor's +parent_class+ pushes the Generated Class into a
      #     subclass of the user-supplied class — semantic legitimacy
      #     enforced by +Validators::SymbolBodyDispatch+ in S18.2, runtime
      #     errors are Ruby-native; the receiver keeps the call from being
      #     shadowed by the emitted bodies' locals, see {call_expression}).
      #   * Callable → today's arity-specialized
      #     +@cb_<name>.call(record, context, scope)+ — unchanged from
      #     pre-S18 emit, byte-identical for every existing snapshot.
      # - *Callable arity* — when the body is a Callable, the call
      #   expression is specialized per arity per
      #   +docs/code_gen/descriptor.md § Callable arity+. Arity is read off the
      #   Callable at +Compile+ time (the +callable_arity+ validator from
      #   S4.1, widened in S17.1 to +0..3+ and widened in S18.2 to skip
      #   Symbol bodies, has already pre-checked it lies in +{0, 1, 2,
      #   3}+, so no validation here):
      #   * +0+: +@cb_<name>.call+
      #   * +1+: +@cb_<name>.call(record)+
      #   * +2+: +@cb_<name>.call(record, context)+
      #   * +3+: +@cb_<name>.call(record, context, scope)+
      #   No splat, no shared helper, no wrapper — the emitted Ruby reads
      #   exactly as one of the four call forms above per
      #   +docs/code_gen/code-generation.md § Callable hoisting+.
      #
      # Both entries wrap the call in two nested guards:
      #
      # 1. +unless filters.drops?(<index>) ... end+ — the codegen-time
      #    Filter wrapper per +docs/code_gen/filters.md § Threading through
      #    Composition+. A filter-dropped Method Attribute never invokes
      #    its body, so the dispatch + +equal?(SKIP)+ pair is completely
      #    elided when the Filter says no.
      # 2. Inside it, +unless value.equal?(Panko::CodeGen::SKIP)+.
      #    The +equal?+ check is load-bearing — +==+ would let an
      #    +==+-overriding object accidentally collide with +SKIP+ per
      #    +docs/code_gen/descriptor.md § SKIP sentinel+.
      #
      # Per-record +@object+ / +@context+ / +@scope+ ivars are reachable
      # from a Symbol-body method on +self+ because +RecordAccess+'s
      # dispatch sites prepend them at the top of +_write_one+ /
      # +_to_hash+ (Specialized) or the +_write_one+ / +_to_hash+
      # dispatchers (Generic) when +descriptor.parent_class+ is non-nil
      # per S18.3 — a deliberate deviation from the "GC ivars are
      # init-time constants" pattern in +docs/code_gen/code-generation.md+,
      # bench-validated as a same-ish-noise-level delta.
      module MethodAttribute
        # Emits the JSON-mode write for one +MethodAttribute+. Two
        # nested guards: outer +unless filters.drops?(<index>) ... end+
        # (filter-side); inner +unless value.equal?(Panko::CodeGen::SKIP)+
        # (SKIP-side, after the Callable runs). Inside the inner guard
        # one line: +writer.push_value(value, "<name>")+ — the 2-arg form
        # collapses the +push_key+ + +push_value+ pair into a single
        # C-extension dispatch (byte-identical output, fewer dispatches).
        #
        # @param method_attribute [Panko::CodeGen::MethodAttribute] the Field node
        # @param index [Integer] codegen-time +FIELD_INDEX+ position used
        #   in the +unless filters.drops?(<index>)+ wrapper
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(method_attribute, index, builder)
          builder.line "unless filters.drops?(#{index})"
          builder.indent do
            builder.line "value = #{call_expression(method_attribute)}"
            builder.line "unless value.equal?(Panko::CodeGen::SKIP)"
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
        # +unless value.equal?(Panko::CodeGen::SKIP)+. Inside the
        # inner guard one line:
        # +result[<key>] = Panko::CodeGen.cast_datetime(value)+ — the cast
        # reproduces Panko's C-ext datetime→ISO-8601 String formatting for Hash
        # mode (a no-op for non-datetime values). The output-key
        # shape comes from +output_key_type+ — +:string+ (default) emits
        # +result["<name>"]+, +:symbol+ emits +result[:<name>]+.
        #
        # @param method_attribute [Panko::CodeGen::MethodAttribute] the Field node
        # @param output_key_type [Symbol] +:string+ or +:symbol+ — the
        #   pre-validated value of +Config#hash_output_key_type+
        # @param index [Integer] codegen-time +FIELD_INDEX+ position used
        #   in the +unless filters.drops?(<index>)+ wrapper
        # @param builder [Panko::CodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash(method_attribute, output_key_type, index, builder)
          key_lit = case output_key_type
          when :symbol then ":#{method_attribute.name}"
          else %("#{method_attribute.name}")
          end
          builder.line "unless filters.drops?(#{index})"
          builder.indent do
            builder.line "value = #{call_expression(method_attribute)}"
            builder.line "unless value.equal?(Panko::CodeGen::SKIP)"
            builder.indent do
              builder.line "result[#{key_lit}] = Panko::CodeGen.cast_datetime(value)"
            end
            builder.line "end"
          end
          builder.line "end"
        end

        # Returns the body-kind-specialized call expression for one
        # +MethodAttribute+. Branches on +body.is_a?(Symbol)+ per S18.3:
        # Symbol bodies emit +self.<method_name>+ — the explicit receiver
        # is load-bearing, since the emitted bodies have +record+ /
        # +writer+ / +context+ / +scope+ / +filters+ / +value+ / +result+
        # locals in scope and a bare token for a user method with any of
        # those names would silently resolve to the local (+value = value+
        # even self-shadows to +nil+). +self.+ also reaches a method made
        # private after definition (legal since Ruby 2.7). Callable bodies
        # emit today's arity-specialized +@cb_<name>.call(...)+, pre-
        # validated by the +callable_arity+ rule (S4.1, widened to
        # +0..3+ in S17.1, widened in S18.2 to skip Symbol bodies) so
        # only arities +0+, +1+, +2+, +3+ ever reach this method.
        # Specialization is per +docs/code_gen/descriptor.md § Callable arity+ —
        # no splat / +*args+ / shared helper. Arity 3 threads +scope+
        # positionally as the third argument; arity 2 keeps its
        # +(record, context)+ meaning (no +scope+ leak).
        #
        # @param method_attribute [Panko::CodeGen::MethodAttribute]
        #   the Field node; +#body+ is either a +Symbol+ or a Callable
        # @return [String] Ruby source — +"self.greeting"+ for a Symbol
        #   body named +:greeting+; +"@cb_full_title.call(record, context)"+
        #   for an arity-2 Callable body on a Field named +:full_title+
        def self.call_expression(method_attribute)
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
end
