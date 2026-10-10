# frozen_string_literal: true

module Panko::CodeGen
  # Fiber-local stack of Generated Class instances. An instance cannot be shared: writing a record
  # can set +@object+/+@context+/+@scope+, so a nested serialize of the same class needs its own.
  #
  # After a code reload or SerializerCache.reset!, each fiber keeps its old stack (and the old
  # class) until it ends. Accepted: reloads are a development feature and reset! is for tests.
  class InstancePool
    def initialize(key, compiled, descriptor)
      # The pool's own object_id keeps a pool rebuilt after SerializerCache.reset! off the old
      # pool's stacks, which hold instances of the old compiled class.
      @key = :"#{key}_#{object_id}"
      @compiled = compiled
      @descriptor = descriptor
    end

    # Returns the stack itself so a checkout and checkin cost one +Thread.current+ lookup.
    def stack
      Thread.current[@key] ||= []
    end

    def build
      @compiled.new(descriptor: @descriptor)
    end
  end
end
