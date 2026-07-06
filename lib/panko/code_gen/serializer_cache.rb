# frozen_string_literal: true

require_relative "../code_gen"
require_relative "descriptor_builder"

module Panko
  module CodeGen
    # Per-serializer-class cache of compiled Generated Classes, one per output
    # mode. This is the caller-side cache the engine deliberately does not keep
    # (docs/merging-into-panko.md § Compile cache stays in Panko).
    #
    # Panko's DSL is generic-only (models: nil), so each (serializer class,
    # mode) maps to exactly one Generated Class — held in a class ivar,
    # compiled once, read lock-free. The model-keyed dimension from Q9 (the
    # specialized path) is intentionally omitted until a models: DSL exists
    # (§ AR scope); with a single ivar per mode there is no runtime-grown Hash
    # to tear against, so the Q9 copy-on-write machinery isn't needed here.
    #
    # Keyed by class identity: a Rails/Zeitwerk reload mints a new class object
    # with an empty cache, so edits self-heal. Manually reopening a live class
    # after its first serialize is unsupported (documented limitation) — the
    # cached class snapshots the definition at first use.
    #
    # Config is fixed at compile time to the engine defaults, which reproduce
    # Panko 0.8.5's output (string hash keys, :wire_format JSON columns,
    # pooled writer). It is an invariant of the cache key, not a dimension.
    module SerializerCache
      IVARS = {json: :@_compiled_json, hash: :@_compiled_hash}.freeze

      # Guards the rare compile-miss. Reads never take it — an ivar read is
      # atomic under the GVL, so a concurrent writer is observed as either nil
      # or the finished class, never a half-built value.
      COMPILE_MUTEX = Mutex.new

      # @param serializer_class [Class] a Panko::Serializer subclass
      # @param output [Symbol] :json or :hash
      # @return [Class] the compiled Generated Class for that (class, mode)
      def self.fetch(serializer_class, output:)
        ivar = IVARS.fetch(output)

        compiled = serializer_class.instance_variable_get(ivar)
        return compiled if compiled

        COMPILE_MUTEX.synchronize do
          compiled = serializer_class.instance_variable_get(ivar)
          return compiled if compiled

          descriptor = DescriptorBuilder.from_panko_descriptor(serializer_class._descriptor)
          compiled = Panko::CodeGen.compile(descriptor, output: output, config: Config.new)
          serializer_class.instance_variable_set(ivar, compiled)
          compiled
        end
      end
    end
  end
end
