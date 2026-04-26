# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    module FieldEmitters
      # Emits the per-mode write for one +MethodAttribute+ inside a
      # +_write_one_*+ / +_to_hash_*+ helper. Two axes of variation:
      #
      # - *Output Mode* — JSON emits +writer.push_key+ + +writer.push_value+;
      #   Hash emits +result[<key>] = value+. One module, one entry per mode,
      #   per +docs/output-modes.md § Composition across modes+.
      # - *Callable arity* — the call expression is specialized per arity
      #   per +docs/descriptor.md § Callable arity+. Arity is read off the
      #   Callable at +Compile+ time (the +callable_arity+ validator from
      #   S4.1 has already pre-checked it lies in +{0, 1, 2}+, so no
      #   validation here):
      #   * +0+: +@cb_<name>.call+
      #   * +1+: +@cb_<name>.call(record)+
      #   * +2+: +@cb_<name>.call(record, context)+
      #   No splat, no shared helper, no wrapper — the emitted Ruby reads
      #   exactly as one of the three call forms above per
      #   +docs/code-generation.md § Callable hoisting+.
      #
      # Both entries wrap the call in the +SKIP+ identity guard:
      # +unless value.equal?(SerializersCodeGen::SKIP)+. The +equal?+
      # check is load-bearing — +==+ would let an +==+-overriding object
      # accidentally collide with +SKIP+ per
      # +docs/descriptor.md § SKIP sentinel+.
      module MethodAttribute
        # Emits the JSON-mode write for one +MethodAttribute+. Three lines
        # under +unless value.equal?(SerializersCodeGen::SKIP)+:
        # +value = @cb_<name>.call(...)+, +writer.push_key("<name>")+,
        # +writer.push_value(value)+.
        #
        # @param method_attribute [SerializersCodeGen::MethodAttribute] the Field node
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_json(method_attribute, builder)
          builder.line "value = #{call_expression(ivar_name(method_attribute), method_attribute.body.arity)}"
          builder.line "unless value.equal?(SerializersCodeGen::SKIP)"
          builder.indent do
            builder.line %(writer.push_key("#{method_attribute.name}"))
            builder.line "writer.push_value(value)"
          end
          builder.line "end"
        end

        # Emits the Hash-mode write for one +MethodAttribute+. One body
        # line under +unless value.equal?(SerializersCodeGen::SKIP)+:
        # +result[<key>] = value+. The output-key shape comes from
        # +output_key_type+ — +:string+ (default) emits +result["<name>"]+,
        # +:symbol+ emits +result[:<name>]+.
        #
        # @param method_attribute [SerializersCodeGen::MethodAttribute] the Field node
        # @param output_key_type [Symbol] +:string+ or +:symbol+ — the
        #   pre-validated value of +Config#hash_output_key_type+
        # @param builder [SerializersCodeGen::CodeBuilder] target buffer
        # @return [void]
        def self.emit_hash(method_attribute, output_key_type, builder)
          key_lit = case output_key_type
          when :symbol then ":#{method_attribute.name}"
          else %("#{method_attribute.name}")
          end
          builder.line "value = #{call_expression(ivar_name(method_attribute), method_attribute.body.arity)}"
          builder.line "unless value.equal?(SerializersCodeGen::SKIP)"
          builder.indent do
            builder.line "result[#{key_lit}] = value"
          end
          builder.line "end"
        end

        # Returns the arity-specialized call expression for one ivar. Pre-
        # validated by the +callable_arity+ rule (S4.1) — only +0+, +1+,
        # +2+ ever reach this method. Specialization is per
        # +docs/descriptor.md § Callable arity+ — no splat / +*args+ / shared
        # helper.
        #
        # @param ivar_name [String] the +@cb_<name>+ ivar to invoke
        # @param arity [Integer] +0+, +1+, or +2+
        # @return [String] Ruby source like +"@cb_full_title.call(record, context)"+
        def self.call_expression(ivar_name, arity)
          case arity
          when 0 then "#{ivar_name}.call"
          when 1 then "#{ivar_name}.call(record)"
          else "#{ivar_name}.call(record, context)"
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
