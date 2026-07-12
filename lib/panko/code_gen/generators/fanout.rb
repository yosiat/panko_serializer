# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Multi-file fan-out emitter for {Dump} per
    # +docs/code_gen/dumping.md § Nested Descriptor dumps+: walks the
    # +Descriptor+ tree once, identity-keyed (+__id__+) to dedupe
    # shared and recursive nodes, and produces one complete
    # +.rb+ file's content per unique +Descriptor+. Each file
    # carries its own +# frozen_string_literal: true+ pragma,
    # banner, +require_relative+ directives for every other unique
    # +Descriptor+ it references via Association, and the single
    # +<Name>_<Suffix>+ class body.
    #
    # The per-class class bytes are sourced by reusing
    # {JsonMode#emit_class} / {HashMode#emit_class} unchanged — the
    # fan-out path adds wrapping (pragma, banner, +require_relative+),
    # not new code-gen behavior. Self-loop Associations (Recursive
    # Descriptor → itself) emit zero +require_relative+ directives:
    # the +@<name>_serializer = self+ shortcut from S8.1 resolves the
    # cycle inside the constructor with no inter-file dependency.
    # Mutual-recursion cycles (Folder ↔ Item per S8.2) produce two
    # files that +require_relative+ each other; Ruby's load semantics
    # tolerate this because constants are resolved at instantiation
    # (inside +.new+) — by the time +Folder.new+ allocates an
    # +Item.new+, both files have finished loading and both
    # constants are defined.
    module Fanout
      module_function

      # Returns one entry per unique +Descriptor+ reachable from
      # +descriptor+, in tree post-order (children before parents)
      # so the array can also drive a single +module_eval+ via
      # +Array#flat_map(&:source)+ if a future caller wants
      # the same byte stream Compile evaluates.
      #
      # @param descriptor [Panko::CodeGen::Descriptor] tree root
      # @param output [Symbol] +:json+ or +:hash+
      # @param config [Panko::CodeGen::Config] resolved settings
      # @return [Array<Hash>] each entry has +:descriptor+
      #   (the +Descriptor+ for this file), +:basename+ (filename
      #   without directory, including +.rb+) and +:source+ (the
      #   complete +.rb+ file's bytes).
      def emit_files(descriptor, output:, config:)
        cyclic_ids = CycleMembership.cyclic_descriptor_ids(descriptor)
        DescriptorWalk.in_emit_order(descriptor).map do |desc|
          {
            descriptor: desc,
            basename: basename_for(desc, output),
            source: build_file(desc, output, config, cyclic_ids)
          }
        end
      end

      # Returns the on-disk filename (no directory) for +descriptor+'s
      # per-class file under +output+: snake_case +Descriptor#name+
      # plus +"_<output>.rb"+. Deterministic so two dumps of the same
      # +Descriptor+ + +Output Mode+ resolve to the same file path
      # (the determinism guarantee in the slice acceptance).
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @param output [Symbol] +:json+ or +:hash+
      # @return [String] e.g. +"nested_composition_post_serializer_json.rb"+
      def basename_for(descriptor, output)
        "#{snake_case(descriptor.name)}_#{output}.rb"
      end

      # @!visibility private
      def snake_case(camel)
        camel.gsub(/(?<=.)([A-Z])/, '_\1').downcase
      end
      private_class_method :snake_case

      # Builds one complete +.rb+ file: pragma, banner, +require_relative+
      # for every non-self associated +Descriptor+ (deduped, in
      # Association declaration order — the source-of-truth ordering
      # the slice's acceptance guarantees), then the single
      # +<Name>_<Suffix>+ class body via the per-mode emitter.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @param output [Symbol]
      # @param config [Panko::CodeGen::Config]
      # @param cyclic_ids [Hash{Integer => true}]
      # @return [String]
      def build_file(descriptor, output, config, cyclic_ids)
        builder = CodeBuilder.new
        builder.line "# frozen_string_literal: true"
        builder.blank
        Banner.emit(builder, descriptor, output: output, config: config)
        deps = ordered_dependencies(descriptor)
        deps.each do |dep|
          builder.line %(require_relative "#{snake_case(dep.name)}_#{output}")
        end
        builder.blank if deps.any?
        per_mode_emitter(output).emit_class(descriptor, config, builder, cyclic_ids)
        builder.to_s + "\n"
      end
      private_class_method :build_file

      # Returns the unique non-self +Descriptor+ targets of this
      # +Descriptor+'s +Associations+, in Association declaration
      # order with first-seen wins. Self-loops are excluded — they
      # need no +require_relative+ because the +@<name>_serializer
      # = self+ shortcut from S8.1 lives inside the constructor.
      # Mutual-cycle peers are included; each peer's own file then
      # +require_relative+s back, which Ruby tolerates because
      # the cycle is resolved at instantiation, not at load.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @return [Array<Panko::CodeGen::Descriptor>]
      def ordered_dependencies(descriptor)
        seen = {descriptor.__id__ => true}
        deps = []
        descriptor.associations.each do |assoc|
          target = assoc.descriptor
          next if seen[target.__id__]
          seen[target.__id__] = true
          deps << target
        end
        deps
      end
      private_class_method :ordered_dependencies

      # Returns the per-mode emitter instance whose +#emit_class+ the
      # fan-out path calls. Symmetric with the dispatch in
      # {Generator#emit}; raises the same +ArgumentError+ on an
      # unknown mode.
      #
      # @param output [Symbol]
      # @return [JsonMode, HashMode]
      # @raise [ArgumentError] when +output+ is not in
      #   {Generator::OUTPUT_MODES}
      def per_mode_emitter(output)
        case output
        when :json then JsonMode.new
        when :hash then HashMode.new
        else
          raise ArgumentError, "unknown output mode #{output.inspect}; must be one of #{Generator::OUTPUT_MODES.inspect}"
        end
      end
      private_class_method :per_mode_emitter
    end
  end
end
