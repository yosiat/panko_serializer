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
          emit_initialize(descriptor, builder)
          builder.blank
          emit_serialize_one(builder)
          builder.blank
          emit_serialize_many(builder)
          builder.blank
          RecordAccess::Generic.emit_json(descriptor, config, builder)
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

      # Emits the public +serialize_one+ method. Allocates a fresh
      # +Oj::StringWriter+ per call (Writer lifecycle per
      # +docs/output-modes.md § Writer lifecycle+), threads it through
      # +_write_one+, and returns +writer.to_s+. The +filters+ kwarg is
      # accepted from day 1 to keep the public signature locked
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
          builder.line "writer = Oj::StringWriter.new(mode: :rails)"
          builder.line "_write_one(record, writer, context, filters)"
          builder.line "writer.to_s.chomp"
        end
        builder.line "end"
      end

      # Emits the public +serialize_many+ method. Allocates a fresh
      # +Oj::StringWriter+, opens a top-level JSON array, dispatches each
      # element through +_write_one+, then closes the array
      # (per +docs/output-modes.md § :json+). The +filters+ kwarg is
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
          builder.line "writer = Oj::StringWriter.new(mode: :rails)"
          builder.line "writer.push_array"
          builder.line "records.each { |r| _write_one(r, writer, context, filters) }"
          builder.line "writer.pop"
          builder.line "writer.to_s.chomp"
        end
        builder.line "end"
      end
    end
  end
end
