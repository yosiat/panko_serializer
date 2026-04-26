# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    # Top-level JSON-mode emitter. Walks the Descriptor tree and produces a
    # source string containing one +<Name>_JSON+ class per unique Descriptor
    # in the tree, with children appearing before parents so each parent
    # constructor's reference to its nested +<Inner>_JSON+ class resolves
    # at module_eval time. Mirror of S3.1's +HashMode+ for +:json+ mode
    # per +docs/output-modes.md § :json+.
    #
    # Per +docs/code-generation.md § Generator shape+, the emitter is a
    # tree-of-emitters: this class emits the per-Descriptor class shells,
    # delegates +_write_one+-family emit to the chosen +RecordAccess+
    # strategy (Generic here; Specialized in S6) which in turn delegates
    # per-Field emit to the +FieldEmitters+ family
    # (+Attribute+, +Association+).
    #
    # Composition wiring lands in S5.1: each Association gets an
    # +@<name>_serializer+ ivar hoisted in the constructor pointing at
    # one nested Generated Class instance — the call site in
    # +_write_one_*+ stays monomorphic per
    # +docs/compilation.md § Composition of nested Associations+.
    class JsonMode
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
        cyclic_ids = CycleMembership.cyclic_descriptor_ids(descriptor)
        DescriptorWalk.in_emit_order(descriptor).each_with_index do |desc, i|
          builder.blank if i > 0
          emit_class(desc, config, builder, cyclic_ids)
        end
        builder.to_s + "\n"
      end

      private

      # Emits one +<Name>_JSON+ class shell with constructor + public
      # entries + the chosen +RecordAccess+ strategy's helpers.
      # Strategy choice is per-Descriptor and keyed off
      # +descriptor.models.nil?+ per +docs/compilation.md § Record-access
      # strategy+: +nil+ → +RecordAccess::Generic+ (Hash + PORO via the
      # +_write_one_hash+ / +_write_one_object+ split); set →
      # +RecordAccess::Specialized+ (single +_write_one+ body, no Hash
      # branch).
      #
      # @param descriptor [SerializersCodeGen::Descriptor]
      # @param config [SerializersCodeGen::Config]
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @param cyclic_ids [Hash{Integer => true}] identity-keyed set of
      #   Descriptor +__id__+s that participate in a mutual-recursion
      #   cycle (per {CycleMembership.cyclic_descriptor_ids}); the
      #   constructor branches on +cyclic_ids[descriptor.__id__]+ to
      #   decide whether to emit the +_construct_cache:+ kwarg + cache
      #   threading
      # @return [void]
      def emit_class(descriptor, config, builder, cyclic_ids)
        builder.line "class #{descriptor.name}_JSON"
        builder.indent do
          emit_initialize(descriptor, builder, cyclic_ids)
          builder.blank
          emit_serialize_one(builder)
          builder.blank
          emit_serialize_many(builder)
          builder.blank
          if descriptor.models.nil?
            RecordAccess::Generic.emit_json(descriptor, config, builder)
          else
            RecordAccess::Specialized.emit_json(descriptor, config, builder)
          end
        end
        builder.line "end"
      end

      # Emits the +initialize(descriptor:)+ constructor. Hoists each
      # Method Attribute's Callable body into a per-Field +@cb_<name>+
      # ivar in declaration order per
      # +docs/code-generation.md § Callable hoisting+, then per Association
      # hoists the optional +if:+ Callable into +@cb_if_<name>+ (only when
      # +assoc.if+ is non-+nil+ — unguarded Associations pay zero
      # construction cost) and assigns +@<name>_serializer = <Inner>_JSON
      # .new(descriptor: descriptor.associations[<i>].descriptor)+ — the
      # Composition wiring from
      # +docs/compilation.md § Composition of nested Associations+.
      #
      # When an Association's nested Descriptor is the parent itself
      # (+assoc.descriptor.equal?(descriptor)+ — the self-recursion
      # signal per +docs/descriptor.md § Recursive Descriptors+ +
      # +docs/compilation.md § Recursive Descriptors+), the constructor
      # emits +@<name>_serializer = self+ instead of allocating a nested
      # instance. Detection is identity-based, never structural — two
      # structurally-equal but distinct Descriptors compile to distinct
      # classes by design. The +self+ shortcut breaks what would
      # otherwise be an infinite +.new+ chain at construction time.
      #
      # When the Descriptor participates in a *mutual-recursion* cycle
      # (+cyclic_ids[descriptor.__id__]+ → +true+ per
      # {CycleMembership.cyclic_descriptor_ids}), the constructor
      # signature gains the internal +_construct_cache:+ kwarg
      # (defaulting to a fresh +{}+) and the body's first line registers
      # +self+ in the cache under +descriptor.__id__+ — *before*
      # allocating any nested ivars, so a cycle back to this Descriptor
      # finds the in-progress instance. Each cyclic-child Association
      # then allocates via the +cache[d.__id__] ||= NestedClass.new(
      # descriptor: ..., _construct_cache: cache)+ idiom so the cycle
      # produces exactly one Generated Class instance per unique
      # Descriptor per +docs/compilation.md § Recursive Descriptors+.
      # Acyclic Descriptors stay on the no-kwarg constructor and call
      # nested classes via the plain +.new(descriptor: ...)+ form — no
      # +_construct_cache:+ kwarg leakage and no Hash allocation. A
      # nested Association whose target is acyclic also stays on the
      # plain form (the cycle, by definition, doesn't pass through
      # acyclic nodes).
      #
      # Body is empty when the Descriptor has neither Method Attributes
      # nor Associations (the +shallow_generic+ case).
      #
      # @param descriptor [SerializersCodeGen::Descriptor]
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @param cyclic_ids [Hash{Integer => true}] identity-keyed set of
      #   cyclic Descriptor +__id__+s for the whole tree
      # @return [void]
      def emit_initialize(descriptor, builder, cyclic_ids)
        cyclic_self = cyclic_ids[descriptor.__id__]
        signature = cyclic_self ? "def initialize(descriptor:, _construct_cache: {})" : "def initialize(descriptor:)"
        builder.line signature
        builder.indent do
          builder.line "_construct_cache[descriptor.__id__] = self" if cyclic_self
          descriptor.method_attributes.each_with_index do |method_attribute, index|
            ivar = FieldEmitters::MethodAttribute.ivar_name(method_attribute)
            builder.line "#{ivar} = descriptor.method_attributes[#{index}].body"
          end
          descriptor.associations.each_with_index do |assoc, i|
            if assoc.if
              builder.line "#{FieldEmitters::Association.ivar_name(assoc)} = descriptor.associations[#{i}].if"
            end
            builder.line emit_serializer_assignment(descriptor, assoc, i, "JSON", cyclic_ids)
          end
        end
        builder.line "end"
      end

      # Returns the Ruby source line assigning +@<assoc.name>_serializer+
      # in the constructor. Three branches per the recursion contract:
      #
      # - Self-loop (+assoc.descriptor.equal?(descriptor)+) → +self+
      #   shortcut (S8.1).
      # - Cyclic child of a cyclic parent → cache-threaded
      #   +(_construct_cache[..__id__] ||= NestedClass.new(...,
      #   _construct_cache: _construct_cache))+ (S8.2).
      # - Otherwise → plain +NestedClass.new(descriptor: ...)+ (the
      #   acyclic case from S5).
      #
      # The cyclic-child branch fires only when *both* parent and child
      # are cyclic. A cyclic parent allocating an acyclic child (e.g.,
      # an off-cycle leaf) still uses the plain form — the acyclic
      # child's constructor doesn't accept +_construct_cache:+, and no
      # cycle passes through it, so cache threading would be a kwarg
      # mismatch with no benefit.
      #
      # @param descriptor [SerializersCodeGen::Descriptor] the parent
      # @param assoc [SerializersCodeGen::Association] the Association
      # @param i [Integer] the Association's index in
      #   +descriptor.associations+
      # @param suffix [String] +"JSON"+ or +"Hash"+ — the per-mode
      #   Generated Class suffix
      # @param cyclic_ids [Hash{Integer => true}] cyclic-membership map
      # @return [String] one Ruby source line, no trailing newline
      def emit_serializer_assignment(descriptor, assoc, i, suffix, cyclic_ids)
        if assoc.descriptor.equal?(descriptor)
          "@#{assoc.name}_serializer = self"
        elsif cyclic_ids[descriptor.__id__] && cyclic_ids[assoc.descriptor.__id__]
          "@#{assoc.name}_serializer = (_construct_cache[descriptor.associations[#{i}].descriptor.__id__] ||= " \
            "#{assoc.descriptor.name}_#{suffix}.new(descriptor: descriptor.associations[#{i}].descriptor, _construct_cache: _construct_cache))"
        else
          "@#{assoc.name}_serializer = #{assoc.descriptor.name}_#{suffix}.new(descriptor: descriptor.associations[#{i}].descriptor)"
        end
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
