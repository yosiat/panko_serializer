# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    # Top-level JSON-mode emitter. Walks one Descriptor and produces the
    # source string for one +<Name>_JSON+ Generated Class per
    # +docs/output-modes.md § :json+. The HashMode counterpart lands in S3.
    #
    # Per +docs/code-generation.md § Generator shape+, the emitter is a
    # tree-of-emitters: this class emits the class shell, the public entry
    # methods, and delegates +_write_one+ family emit to the chosen
    # +RecordAccess+ strategy (Generic here; Specialized in S6) which in
    # turn delegates per-Field emit to the +FieldEmitters+ family.
    class JsonMode
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
        builder.line "class #{descriptor.name}_JSON"
        builder.indent do
          emit_initialize(builder)
          builder.blank
          emit_serialize_one(builder)
          builder.blank
          RecordAccess::Generic.emit_json(descriptor, config, builder)
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

      # Emits the public +serialize_one+ method. Allocates a fresh
      # +Oj::StringWriter+ per call (Writer lifecycle per
      # +docs/output-modes.md § Writer lifecycle+), threads it through
      # +_write_one+, and returns +writer.to_s+. The +filters+ kwarg is
      # accepted from day 1 to keep the public signature locked
      # (per +docs/filters.md § Phase-1 behavior+); the phase-1
      # +NotImplementedError+ on non-nil ships in S2.3.
      #
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_serialize_one(builder)
        builder.line "def serialize_one(record, context: nil, filters: nil)"
        builder.indent do
          builder.line "writer = Oj::StringWriter.new(mode: :rails)"
          builder.line "_write_one(record, writer, context, filters)"
          builder.line "writer.to_s.chomp"
        end
        builder.line "end"
      end
    end
  end
end
