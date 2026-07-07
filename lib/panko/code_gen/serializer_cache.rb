# frozen_string_literal: true

require_relative "../code_gen"
require_relative "descriptor_builder"

module Panko
  module CodeGen
    # Per-serializer-class cache of compiled Generated Classes, one per output
    # mode, plus the (mode-agnostic) converted Descriptor. This is the
    # caller-side cache the engine deliberately does not keep
    # (docs/merging-into-panko.md § Compile cache stays in Panko).
    #
    # Panko's DSL is generic-only (models: nil), so each (serializer class,
    # mode) maps to exactly one Generated Class — held in a class ivar,
    # compiled once, read lock-free. The model-keyed dimension from Q9 (the
    # specialized path) is intentionally omitted until a models: DSL exists
    # (§ AR scope); with a single ivar per mode there is no runtime-grown Hash
    # to tear against, so the Q9 copy-on-write machinery isn't needed here.
    #
    # The converted Descriptor is cached too and shared between compile and
    # instantiation: a Generated Class with associations reads
    # +descriptor.associations+ in its constructor to build child serializers,
    # so +.new(descriptor:)+ must receive the same Descriptor it was compiled
    # from.
    #
    # Keyed by class identity: a Rails/Zeitwerk reload mints a new class object
    # with an empty cache, so edits self-heal. Manually reopening a live class
    # after its first serialize is unsupported (documented limitation).
    #
    # Config is fixed at compile time to the engine defaults, which reproduce
    # Panko 0.8.5's output (string hash keys, :wire_format JSON columns,
    # pooled writer). It is an invariant of the cache key, not a dimension.
    module SerializerCache
      COMPILED_IVARS = {json: :@_compiled_json, hash: :@_compiled_hash}.freeze
      DESCRIPTOR_IVAR = :@_codegen_descriptor

      # Guards the rare compile/convert miss. Reads never take it — an ivar
      # read is atomic under the GVL, so a concurrent writer is observed as
      # either nil or the finished value, never a half-built one.
      COMPILE_MUTEX = Mutex.new

      # @param serializer_class [Class] a Panko::Serializer subclass
      # @param output [Symbol] :json or :hash
      # @return [Class] the compiled Generated Class for that (class, mode)
      def self.fetch(serializer_class, output:)
        ivar = COMPILED_IVARS.fetch(output)

        compiled = serializer_class.instance_variable_get(ivar)
        return compiled if compiled

        # Convert outside the compile lock (it takes the lock itself); the two
        # acquisitions are sequential, never re-entrant.
        descriptor = descriptor_for(serializer_class)

        COMPILE_MUTEX.synchronize do
          compiled = serializer_class.instance_variable_get(ivar)
          return compiled if compiled

          compiled = Panko::CodeGen.compile(descriptor, output: output, config: Config.new)
          serializer_class.instance_variable_set(ivar, compiled)
          compiled
        end
      end

      # @param serializer_class [Class] a Panko::Serializer subclass
      # @return [Panko::CodeGen::Descriptor] the converted, cached Descriptor
      def self.descriptor_for(serializer_class)
        cached = serializer_class.instance_variable_get(DESCRIPTOR_IVAR)
        return cached if cached

        COMPILE_MUTEX.synchronize do
          cached = serializer_class.instance_variable_get(DESCRIPTOR_IVAR)
          return cached if cached

          descriptor = DescriptorBuilder.build(serializer_class)
          serializer_class.instance_variable_set(DESCRIPTOR_IVAR, descriptor)
          descriptor
        end
      end
    end
  end
end
