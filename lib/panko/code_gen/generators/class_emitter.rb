# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # The one class-shell emitter, mode-agnostic behind a {Sink}. Walks
    # the Descriptor tree and produces a source string containing one
    # +<Name>_<suffix>+ class per unique Descriptor, children before
    # parents (post-order) so each parent constructor's reference to its
    # nested class resolves at +module_eval+ time. The byte payload feeds
    # both +Compiler+ (+module_eval+) and +Dump+ (+File.write+).
    #
    # Everything here is mode-shared by construction: the constructor's
    # Callable hoisting and Composition wiring, the recursion contract,
    # the +root_key+ validator. The sink supplies what genuinely
    # diverges — per-class constants, the +serialize_one+/+serialize_many+
    # bodies, and every leaf write shape (via {RecordAccess} + {FieldWalk}).
    class ClassEmitter
      # @param sink [Panko::CodeGen::Generators::Sink] the Output Mode adapter
      def initialize(sink)
        @sink = sink
      end

      # Emits the full source for the Generated Class tree rooted at
      # +descriptor+.
      #
      # @param descriptor [Panko::CodeGen::Descriptor] the root input
      # @param config [Panko::CodeGen::Config] resolved settings
      # @return [String] the emitted Ruby source
      def emit(descriptor, config)
        builder = CodeBuilder.new
        builder.line "# frozen_string_literal: true"
        builder.blank
        Banner.emit(builder, descriptor, output: @sink.output, config: config)
        cyclic_ids = CycleMembership.cyclic_descriptor_ids(descriptor)
        DescriptorWalk.in_emit_order(descriptor).each_with_index do |desc, i|
          builder.blank if i > 0
          emit_class(desc, config, builder, cyclic_ids)
        end
        builder.to_s + "\n"
      end

      # Emits one Generated Class shell: constants, constructor, public
      # entries, +_release+, and the Record-access strategy keyed off
      # +descriptor.model.nil?+ (nil → {RecordAccess::Generic}; set →
      # {RecordAccess::Specialized}).
      #
      # Public so the multi-file fan-out path ({Generators::Fanout}) can
      # compose one class per file without re-running {#emit}'s tree-walk.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @param config [Panko::CodeGen::Config]
      # @param builder [Panko::CodeGen::CodeBuilder] target buffer
      # @param cyclic_ids [Hash{Integer => true}] identity-keyed set of
      #   Descriptor +__id__+s participating in a mutual-recursion cycle
      #   (per {CycleMembership.cyclic_descriptor_ids})
      # @return [void]
      def emit_class(descriptor, config, builder, cyclic_ids)
        field_index = FieldIndex.build(descriptor)
        builder.line class_line(descriptor)
        builder.indent do
          builder.line "#{GeneratedNames.field_index_const} = #{FieldIndex.to_hash_literal(field_index)}.freeze"
          @sink.emit_class_constants(descriptor, config, builder)
          builder.blank
          emit_initialize(descriptor, builder, cyclic_ids)
          builder.blank
          @sink.emit_serialize_one(config, builder)
          builder.blank
          @sink.emit_serialize_many(config, builder)
          builder.blank
          Release.emit(descriptor, builder, cyclic_ids)
          builder.blank
          if descriptor.model.nil?
            RecordAccess::Generic.emit(descriptor, config, field_index, builder, @sink)
          else
            RecordAccess::Specialized.emit(descriptor, config, field_index, builder, @sink)
          end
          if config.supports_root_key
            builder.blank
            emit_validate_root_key(builder)
          end
        end
        builder.line "end"
      end

      private

      # The +class <Name>_<suffix>+ header, branching on
      # +descriptor.parent_class+: +nil+ → bare class (implicit +Object+
      # parent); a named class → +< <parent_class.name>+ spliced verbatim
      # so namespaced parents resolve at +module_eval+ time; an anonymous
      # parent → the +ANON_PARENTS+ registry fetch.
      def class_line(descriptor)
        class_name = GeneratedNames.class_name(descriptor, @sink.suffix)
        if descriptor.parent_class.nil?
          "class #{class_name}"
        elsif descriptor.parent_class.name
          "class #{class_name} < #{descriptor.parent_class.name}"
        else
          "class #{class_name} < ANON_PARENTS.fetch(#{descriptor.name.inspect})"
        end
      end

      # Emits the +initialize(descriptor:)+ constructor: hoists each
      # Callable-bodied Method Attribute into its +@cb_<name>+ ivar
      # (Symbol bodies dispatch on +self+ at the emit site — nothing to
      # bind), hoists each Association's optional +if:+ Callable, then
      # wires Composition via {#emit_serializer_assignment}.
      #
      # A Descriptor in a mutual-recursion cycle gains the internal
      # +_construct_cache:+ kwarg and registers +self+ in the cache
      # before allocating any nested ivars, so a cycle back to this
      # Descriptor finds the in-progress instance — one Generated Class
      # instance per unique Descriptor. Acyclic Descriptors stay on the
      # no-kwarg constructor: no kwarg leakage, no Hash allocation.
      def emit_initialize(descriptor, builder, cyclic_ids)
        cyclic_self = cyclic_ids[descriptor.__id__]
        signature = cyclic_self ? "def initialize(descriptor:, _construct_cache: {})" : "def initialize(descriptor:)"
        builder.line signature
        builder.indent do
          builder.line "_construct_cache[descriptor.__id__] = self" if cyclic_self
          descriptor.method_attributes.each_with_index do |method_attribute, index|
            next if method_attribute.body.is_a?(Symbol)
            ivar = GeneratedNames.callable_ivar(method_attribute)
            builder.line "#{ivar} = descriptor.method_attributes[#{index}].body"
          end
          descriptor.associations.each_with_index do |assoc, i|
            if assoc.if
              builder.line "#{GeneratedNames.if_guard_ivar(assoc)} = descriptor.associations[#{i}].if"
            end
            builder.line emit_serializer_assignment(descriptor, assoc, i, cyclic_ids)
          end
        end
        builder.line "end"
      end

      # The Composition-wiring line for one Association. Three branches:
      # a self-loop (+assoc.descriptor.equal?(descriptor)+ — detection is
      # identity-based, never structural) short-circuits to +self+,
      # breaking what would otherwise be an infinite +.new+ chain; a
      # cyclic child of a cyclic parent threads +_construct_cache+ so the
      # cycle produces exactly one instance per unique Descriptor; the
      # acyclic case allocates plainly. The cyclic-child branch fires
      # only when *both* ends are cyclic — a cyclic parent still
      # allocates an off-cycle leaf via the plain form, whose constructor
      # doesn't accept the kwarg.
      def emit_serializer_assignment(descriptor, assoc, i, cyclic_ids)
        ivar = GeneratedNames.serializer_ivar(assoc)
        if assoc.descriptor.equal?(descriptor)
          "#{ivar} = self"
        elsif cyclic_ids[descriptor.__id__] && cyclic_ids[assoc.descriptor.__id__]
          "#{ivar} = (_construct_cache[descriptor.associations[#{i}].descriptor.__id__] ||= " \
            "#{GeneratedNames.class_name(assoc.descriptor, @sink.suffix)}.new(descriptor: descriptor.associations[#{i}].descriptor, _construct_cache: _construct_cache))"
        else
          "#{ivar} = #{GeneratedNames.class_name(assoc.descriptor, @sink.suffix)}.new(descriptor: descriptor.associations[#{i}].descriptor)"
        end
      end

      # The +root_key:+ accepted-types validator: a non-empty String or
      # +nil+ only. Emitted only when the wrap branch is emitted, so the
      # default-config emit pays nothing for the feature being absent.
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
