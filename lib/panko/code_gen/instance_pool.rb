# frozen_string_literal: true

module Panko::CodeGen
  # Fiber-local LIFO stack of Generated Class instances for one
  # (serializer class, output mode), mirroring the engine's WritersPool
  # lifecycle: checkout at the top of a serialize, checkin in ensure.
  #
  # Construction is the expensive part being pooled — +.new(descriptor:)+
  # recursively builds the child-serializer tree, which on association-heavy
  # serializers dominates the per-call seam cost. An instance cannot simply
  # be cached per class: +_write_one+ rewrites +@object+/+@context+/+@scope+
  # per record, so sharing across fibers (or across overlapping
  # serializations on the same fiber, e.g. a method attribute reentering its
  # own serializer class) would corrupt those ivars mid-emit. The LIFO stack
  # preserves fresh-per-call semantics exactly the way WritersPool does for
  # Writers: steady state pops the one warm instance with zero construction,
  # while a reentrant checkout finds the stack empty and constructs a second.
  # Checkin callers run +_release+ on the instance first, so a stacked
  # instance holds no record/context references between calls.
  #
  # A Zeitwerk reload keys fresh slots (new class object → new key) but
  # cannot reclaim the old ones: each long-lived thread that served the old
  # class keeps its stale +Thread.current+ entry — pinning the old class
  # tree — until the thread dies. Bounded by reloads x classes x threads
  # and dev-only, so accepted rather than paying a registry per call.
  class InstancePool
    # @param key [Symbol] unique per (serializer class, output mode) —
    #   the +Thread.current[]+ storage slot (fiber-local in MRI)
    # @param compiled [Class] the Generated Class to construct on pool miss
    # @param descriptor [Panko::CodeGen::Descriptor] the Descriptor the
    #   class was compiled from (its constructor contract)
    def initialize(key, compiled, descriptor)
      @key = key
      @compiled = compiled
      @descriptor = descriptor
    end

    # Returns the live per-fiber stack. Callers pop-or-{#build} at the top of
    # a serialize and push back in ensure — holding the stack in a local
    # keeps the whole checkout/checkin cycle at a single +Thread.current+
    # lookup per call.
    #
    # @return [Array] the per-fiber LIFO stack of Generated Class instances
    def stack
      Thread.current[@key] ||= []
    end

    # @return [Object] a freshly constructed Generated Class instance —
    #   the pool-miss path
    def build
      @compiled.new(descriptor: @descriptor)
    end
  end
end
