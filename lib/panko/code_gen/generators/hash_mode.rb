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
        Banner.emit(builder, descriptor, output: :hash, config: config)
        cyclic_ids = CycleMembership.cyclic_descriptor_ids(descriptor)
        DescriptorWalk.in_emit_order(descriptor).each_with_index do |desc, i|
          builder.blank if i > 0
          emit_class(desc, config, builder, cyclic_ids)
        end
        builder.to_s + "\n"
      end

      # Emits one +<Name>_Hash+ class shell with constructor + public
      # entries + the chosen +RecordAccess+ strategy's helpers. Strategy
      # choice is per-Descriptor and keyed off +descriptor.models.nil?+
      # per +docs/compilation.md § Record-access strategy+: +nil+ →
      # +RecordAccess::Generic+ (Hash + PORO via the +_to_hash_hash+ /
      # +_to_hash_object+ split); set → +RecordAccess::Specialized+
      # (single +_to_hash+ body, no Hash branch).
      #
      # Public so the multi-file fan-out path
      # ({Generators::Fanout}) can compose one class per file —
      # without re-running {#emit}'s tree-walk for every per-file emit.
      # The single-file {#emit} path appends the same per-class bytes
      # in tree post-order to one buffer.
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
        field_index = FieldIndex.build(descriptor)
        builder.line class_line(descriptor, "Hash")
        builder.indent do
          builder.line "FIELD_INDEX = #{FieldIndex.to_hash_literal(field_index)}.freeze"
          builder.blank
          emit_initialize(descriptor, builder, cyclic_ids)
          builder.blank
          emit_serialize_one(config, builder)
          builder.blank
          emit_serialize_many(config, builder)
          builder.blank
          if descriptor.models.nil?
            RecordAccess::Generic.emit_hash(descriptor, config, field_index, builder)
          else
            RecordAccess::Specialized.emit_hash(descriptor, config, field_index, builder)
          end
          if config.supports_root_key
            builder.blank
            emit_validate_root_key(builder)
          end
        end
        builder.line "end"
      end

      private

      # Returns the +class <Name>_Hash+ header line for +descriptor+,
      # branching on +descriptor.parent_class+:
      #
      # - +nil+ → bare +class <Name>_Hash+ (implicit +Object+ parent,
      #   byte-identical to pre-S18 emit so existing snapshots with
      #   +parent_class+ unset stay green).
      # - +Class+ → +class <Name>_Hash < <parent_class.name>+ (the
      #   subclass-dispatch shape from +docs/merging-into-panko.md
      #   § Generated Class subclasses the user's Panko serializer+).
      #   The parent's fully-qualified name is spliced verbatim via
      #   +parent_class.name+ so namespaced parents
      #   (+Outer::Inner::Base+) resolve correctly at +module_eval+
      #   time. Anonymous parents are out of scope for S18 — Panko's
      #   converter always sets a named class.
      #
      # @param descriptor [SerializersCodeGen::Descriptor]
      # @param suffix [String] +"Hash"+ — the per-mode Generated Class
      #   suffix; threaded as a parameter to keep this helper's shape
      #   identical to {JsonMode#class_line}, which passes +"JSON"+
      # @return [String] one Ruby source line, no trailing newline
      def class_line(descriptor, suffix)
        if descriptor.parent_class.nil?
          "class #{descriptor.name}_#{suffix}"
        else
          "class #{descriptor.name}_#{suffix} < #{descriptor.parent_class.name}"
        end
      end

      # Emits the +initialize(descriptor:)+ constructor. Hoists each
      # Method Attribute's Callable body into a per-Field +@cb_<name>+
      # ivar in declaration order per
      # +docs/code-generation.md § Callable hoisting+, then per Association
      # hoists the optional +if:+ Callable into +@cb_if_<name>+ (only when
      # +assoc.if+ is non-+nil+ — unguarded Associations pay zero
      # construction cost) and assigns +@<name>_serializer = <Inner>_Hash
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
            builder.line emit_serializer_assignment(descriptor, assoc, i, "Hash", cyclic_ids)
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

      # Emits the public +serialize_one+ method. Hash mode allocates no
      # Writer (per +docs/output-modes.md § :hash+) — the body is a
      # straight delegate to +_to_hash+, whose return value is the
      # produced Hash. The +filters+ kwarg is accepted from day 1 to
      # keep the public signature locked (per
      # +docs/filters.md § Phase-1 behavior+); the body's first line
      # normalizes it via
      # +SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)+. +nil+
      # and +{}+ collapse to +Filter::NONE+ (allocation-free,
      # +FIELD_INDEX+ is unread on that path); a non-empty Hash routes
      # to the +Filter::Indexed+ cell from S13's verdict (S14.2,
      # +docs/research/filter_experiments_results.md § 1+) — bit-mask
      # rep when +FIELD_INDEX.size <= 63+, Boolean Array otherwise.
      #
      # +scope:+ is a sibling kwarg of +context:+ added in S17.2 — the
      # auth/viewer axis from +docs/merging-into-panko.md § Both `scope`
      # and `context` survive Panko's public DSL+. Defaults to +nil+,
      # threaded positionally into +_to_hash+ between +context+ and
      # +filters+. Arity-3 Callables observe it as the third arg;
      # arity 0/1/2 Callables ignore it (the +call_expression+ in
      # +FieldEmitters::MethodAttribute+ / +FieldEmitters::Association+
      # is specialized per arity).
      #
      # When +Config#supports_root_key+ is +true+, the signature gains
      # an additional +root_key:+ kwarg (defaulting to +nil+); when
      # truthy, the body wraps the produced Hash in a single-entry
      # +{root_key => result}+ (per
      # +docs/generated-class.md § serialize_one+). The kwarg value
      # must be a non-empty String or +nil+ —
      # +validate_root_key!+ raises +ArgumentError+ on anything else.
      # When +supports_root_key+ is +false+, the kwarg is omitted from
      # the signature entirely. +root_key:+ continues to slot last in
      # the signature so its position is preserved across the S17.2
      # +scope:+ widening.
      #
      # @param config [SerializersCodeGen::Config] resolved settings;
      #   +supports_root_key+ gates the +root_key:+ kwarg + wrap branch
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_serialize_one(config, builder)
        signature = config.supports_root_key ?
          "def serialize_one(record, context: nil, scope: nil, filters: nil, root_key: nil)" :
          "def serialize_one(record, context: nil, scope: nil, filters: nil)"
        builder.line signature
        builder.indent do
          builder.line "filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)"
          if config.supports_root_key
            builder.line "validate_root_key!(root_key)"
            builder.line "result = _to_hash(record, context, scope, filters)"
            builder.line "root_key ? {root_key => result} : result"
          else
            builder.line "_to_hash(record, context, scope, filters)"
          end
        end
        builder.line "end"
      end

      # Emits the public +serialize_many+ method. Hash mode allocates no
      # Writer (per +docs/output-modes.md § :hash+) — the body walks the
      # input enumerable with +.map+, calling +_to_hash+ per element, and
      # returns the resulting +Array<Hash>+. The +filters+ kwarg is
      # accepted from day 1 to keep the public signature locked (per
      # +docs/filters.md § Phase-1 behavior+); the body's first line
      # normalizes it via
      # +SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)+ —
      # +nil+ / +{}+ → +Filter::NONE+; a non-empty Hash routes to the
      # +Filter::Indexed+ cell against +FIELD_INDEX+ per S14.2.
      #
      # When +Config#supports_root_key+ is +true+, the signature gains
      # the same +root_key:+ kwarg as +serialize_one+; a truthy value
      # wraps the +Array<Hash>+ in a single-entry +{root_key => result}+,
      # so an empty input still emits +{root_key => []}+ (wrapped empty
      # array, never +nil+, never omitted) per
      # +docs/testing.md § root_key_spec.rb+ (case 6).
      #
      # @param config [SerializersCodeGen::Config] resolved settings;
      #   +supports_root_key+ gates the +root_key:+ kwarg + wrap branch
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_serialize_many(config, builder)
        signature = config.supports_root_key ?
          "def serialize_many(records, context: nil, scope: nil, filters: nil, root_key: nil)" :
          "def serialize_many(records, context: nil, scope: nil, filters: nil)"
        builder.line signature
        builder.indent do
          builder.line "filters = SerializersCodeGen::Filter.wrap(filters, FIELD_INDEX)"
          if config.supports_root_key
            builder.line "validate_root_key!(root_key)"
            builder.line "result = records.map { |r| _to_hash(r, context, scope, filters) }"
            builder.line "root_key ? {root_key => result} : result"
          else
            builder.line "records.map { |r| _to_hash(r, context, scope, filters) }"
          end
        end
        builder.line "end"
      end

      # Emits the private +validate_root_key!+ helper used by the wrap
      # branch of +serialize_one+ / +serialize_many+ when
      # +Config#supports_root_key+ is +true+. Enforces the accepted-types
      # contract from +docs/generated-class.md § serialize_one+: a
      # non-empty +String+ or +nil+ only; empty +String+, +Symbol+, or
      # any other non-+nil+ value raises +ArgumentError+ at call time.
      # Emitted only when the wrap branch is also emitted, so the
      # default-config emit pays zero source-bytes / zero method-table
      # cost from this feature being absent.
      #
      # @param builder [SerializersCodeGen::CodeBuilder] target buffer
      # @return [void]
      def emit_validate_root_key(builder)
        builder.line "private def validate_root_key!(root_key)"
        builder.indent do
          builder.line "return if root_key.nil? || (root_key.is_a?(String) && !root_key.empty?)"
          builder.line %(raise ArgumentError, "root_key: must be a non-empty String, got \#{root_key.inspect}")
        end
        builder.line "end"
      end
    end
  end
end
