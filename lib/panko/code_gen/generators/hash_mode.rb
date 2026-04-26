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
    # S3.2 ships +serialize_many+ alongside +serialize_one+. The
    # +raise NotImplementedError if filters+ phase-1 contract lands in
    # S3.3 — mirror of the JSON-mode S2.1/S2.2/S2.3 split.
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
          emit_initialize(builder)
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

      # Emits the +initialize(descriptor:)+ constructor. Body is empty in
      # this slice — no Callables to hoist, no nested Generated Classes to
      # construct. The shape must still be present so S4/S5 plug in
      # without changing the constructor signature.
      #
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_initialize(builder)
        builder.line "def initialize(descriptor:)"
        builder.line "end"
      end

      # Emits the public +serialize_one+ method. Hash mode allocates no
      # Writer (per +docs/output-modes.md § :hash+) — the body is a
      # straight delegate to +_to_hash+, whose return value is the
      # produced Hash. The +filters+ kwarg is accepted from day 1 to
      # keep the public signature locked
      # (per +docs/filters.md § Phase-1 behavior+); the
      # +raise NotImplementedError if filters+ guard lands in S3.3 —
      # mirror of the JSON-mode S2.1 → S2.3 split.
      #
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_serialize_one(builder)
        builder.line "def serialize_one(record, context: nil, filters: nil)"
        builder.indent do
          builder.line "_to_hash(record, context, filters)"
        end
        builder.line "end"
      end

      # Emits the public +serialize_many+ method. Hash mode allocates no
      # Writer (per +docs/output-modes.md § :hash+) — the body walks the
      # input enumerable with +.map+, calling +_to_hash+ per element, and
      # returns the resulting +Array<Hash>+. The +filters+ kwarg is
      # accepted from day 1 to keep the public signature locked
      # (per +docs/filters.md § Phase-1 behavior+); the
      # +raise NotImplementedError if filters+ guard lands in S3.3 —
      # mirror of the JSON-mode S2.1 → S2.3 split.
      #
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_serialize_many(builder)
        builder.line "def serialize_many(records, context: nil, filters: nil)"
        builder.indent do
          builder.line "records.map { |r| _to_hash(r, context, filters) }"
        end
        builder.line "end"
      end
    end
  end
end
