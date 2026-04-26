# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    # Top-level Hash-mode emitter. Walks one Descriptor and produces the
    # source string for one +<Name>_Hash+ Generated Class per
    # +docs/output-modes.md § :hash+. Parallel — not a subclass — of
    # +JsonMode+ per +docs/output-modes.md § Composition across modes+:
    # the two emit shapes diverge (Writer-pushing vs Hash-mutation) so
    # inheritance would couple distinct evolutionary paths. Shared
    # field-level emit lives in +FieldEmitters::Attribute+; shared
    # record-access shape lives in +RecordAccess::Generic+.
    #
    # S3.3 closes the phase-1 filter contract for Hash mode: the
    # +raise NotImplementedError if filters+ guard at the top of
    # +serialize_one+ and +serialize_many+ — mirror of the JSON-mode
    # S2.1/S2.2/S2.3 split.
    class HashMode
      # Builds and returns the source string for the Generated Class. The
      # string starts with +# frozen_string_literal: true+
      # (per +docs/code-generation.md § Source pragmas+) and is the byte
      # payload that both +Compiler+ (+module_eval+) and +Dump+
      # (+File.write+) consume.
      #
      # @param descriptor [SerializersCodeGen::Descriptor] the input
      # @param config [SerializersCodeGen::Config] resolved settings
      # @return [String] the emitted Ruby source
      def emit(descriptor, config)
        builder = CodeBuilder.new
        builder.line "# frozen_string_literal: true"
        builder.blank
        builder.line "class #{descriptor.name}_Hash"
        builder.indent do
          emit_initialize(descriptor, builder)
          builder.blank
          emit_serialize_one(builder)
          builder.blank
          emit_serialize_many(builder)
          builder.blank
          RecordAccess::Generic.emit_hash(descriptor, config, builder)
        end
        builder.line "end"
        builder.to_s + "\n"
      end

      private

      # Emits the +initialize(descriptor:)+ constructor. Hoists each
      # Method Attribute's Callable body into a per-Field +@cb_<name>+
      # ivar in declaration order per
      # +docs/code-generation.md § Callable hoisting+ — same shape Compile
      # and Dump, no class-constant divergence. Body is empty when the
      # Descriptor has no Method Attributes (the +shallow_generic+ case).
      #
      # @param descriptor [SerializersCodeGen::Descriptor] the input
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_initialize(descriptor, builder)
        builder.line "def initialize(descriptor:)"
        builder.indent do
          descriptor.method_attributes.each_with_index do |method_attribute, index|
            ivar = FieldEmitters::MethodAttribute.ivar_name(method_attribute)
            builder.line "#{ivar} = descriptor.method_attributes[#{index}].body"
          end
        end
        builder.line "end"
      end

      # Emits the public +serialize_one+ method. Hash mode allocates no
      # Writer (per +docs/output-modes.md § :hash+) — the body is a
      # straight delegate to +_to_hash+, whose return value is the
      # produced Hash. The +filters+ kwarg is accepted from day 1 to
      # keep the public signature locked
      # (per +docs/filters.md § Phase-1 behavior+); a non-nil value
      # raises +NotImplementedError+ until the phase-2 implementation
      # lands in S14.
      #
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_serialize_one(builder)
        builder.line "def serialize_one(record, context: nil, filters: nil)"
        builder.indent do
          builder.line "raise NotImplementedError if filters"
          builder.line "_to_hash(record, context, filters)"
        end
        builder.line "end"
      end

      # Emits the public +serialize_many+ method. Hash mode allocates no
      # Writer (per +docs/output-modes.md § :hash+) — the body walks the
      # input enumerable with +.map+, calling +_to_hash+ per element, and
      # returns the resulting +Array<Hash>+. The +filters+ kwarg is
      # accepted from day 1 to keep the public signature locked
      # (per +docs/filters.md § Phase-1 behavior+); a non-nil value
      # raises +NotImplementedError+ until the phase-2 implementation
      # lands in S14.
      #
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_serialize_many(builder)
        builder.line "def serialize_many(records, context: nil, filters: nil)"
        builder.indent do
          builder.line "raise NotImplementedError if filters"
          builder.line "records.map { |r| _to_hash(r, context, filters) }"
        end
        builder.line "end"
      end
    end
  end
end
