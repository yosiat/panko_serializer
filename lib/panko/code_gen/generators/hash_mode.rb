# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    # Top-level Hash-mode emitter. Walks the Descriptor tree and produces a
    # source string containing one +<Name>_Hash+ class per unique Descriptor
    # in the tree, with children appearing before parents so each parent
    # constructor's reference to its nested +<Inner>_Hash+ class resolves
    # at module_eval time. Parallel — not a subclass — of +JsonMode+ per
    # +docs/output-modes.md § Composition across modes+: the two emit
    # shapes diverge (Writer-pushing vs Hash-mutation) so inheritance
    # would couple distinct evolutionary paths. Shared field-level emit
    # lives in +FieldEmitters::Attribute+ / +FieldEmitters::Association+;
    # shared record-access shape lives in +RecordAccess::Generic+.
    #
    # Composition wiring lands in S5.1: each Association gets an
    # +@<name>_serializer+ ivar hoisted in the constructor pointing at
    # one nested Generated Class instance — the call site in
    # +_to_hash_*+ stays monomorphic per
    # +docs/compilation.md § Composition of nested Associations+.
    class HashMode
      # Builds and returns the source string for the Generated Class tree
      # rooted at +descriptor+. The string starts with
      # +# frozen_string_literal: true+ (per
      # +docs/code-generation.md § Source pragmas+), then emits one class
      # per unique Descriptor reachable from +descriptor+, children
      # before parents (post-order). The byte payload feeds both
      # +Compiler+ (+module_eval+) and +Dump+ (+File.write+).
      #
      # @param descriptor [SerializersCodeGen::Descriptor] the root input
      # @param config [SerializersCodeGen::Config] resolved settings
      # @return [String] the emitted Ruby source
      def emit(descriptor, config)
        builder = CodeBuilder.new
        builder.line "# frozen_string_literal: true"
        builder.blank
        DescriptorWalk.in_emit_order(descriptor).each_with_index do |desc, i|
          builder.blank if i > 0
          emit_class(desc, config, builder)
        end
        builder.to_s + "\n"
      end

      private

      # Emits one +<Name>_Hash+ class shell with constructor + public
      # entries + +RecordAccess::Generic+ helpers.
      #
      # @param descriptor [SerializersCodeGen::Descriptor]
      # @param config [SerializersCodeGen::Config]
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_class(descriptor, config, builder)
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
      end

      # Emits the +initialize(descriptor:)+ constructor. Per Association
      # the body assigns +@<name>_serializer = <Inner>_Hash.new(descriptor:
      # descriptor.associations[<i>].descriptor)+ — the Composition wiring
      # from +docs/compilation.md § Composition of nested Associations+.
      # When the Descriptor has no Associations, the body is empty (same
      # shape as S3.1's walking-skeleton emitter).
      #
      # @param descriptor [SerializersCodeGen::Descriptor]
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_initialize(descriptor, builder)
        builder.line "def initialize(descriptor:)"
        builder.indent do
          descriptor.associations.each_with_index do |assoc, i|
            builder.line "@#{assoc.name}_serializer = #{assoc.descriptor.name}_Hash.new(descriptor: descriptor.associations[#{i}].descriptor)"
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
