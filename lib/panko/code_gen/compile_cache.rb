# frozen_string_literal: true

module SerializersCodeGen
  # Identity-keyed map of Descriptor → Generated Class, threaded through
  # +Compiler+'s recursive descent so each unique Descriptor in a tree
  # produces exactly one Generated Class (per
  # +docs/compilation.md § Recursive Descriptors+).
  #
  # Single-entry case only in this slice — the +Compiler+ inserts the
  # top-level Descriptor's class so a future S5 nested-Association walk
  # has a hit on self-recursion. Full cycle handling lands in S8.
  class CompileCache
    # Returns an empty cache. Backing store is a plain Hash keyed by
    # +descriptor.__id__+ — identity, never +#hash+ + +#eql?+, so
    # different-but-equal Descriptors get distinct entries.
    #
    # @return [CompileCache]
    def initialize
      @store = {}
    end

    # Returns the cached Generated Class for +descriptor+, or +nil+ if
    # the descriptor has not been seen yet.
    #
    # @param descriptor [SerializersCodeGen::Descriptor] the lookup key
    # @return [Class, nil] the cached class, or +nil+ on miss
    def get(descriptor)
      @store[descriptor.__id__]
    end

    # Inserts +generated_class+ under +descriptor+'s identity. Returns
    # the inserted class so callers can chain +cache.set(d, klass)+.
    #
    # @param descriptor [SerializersCodeGen::Descriptor] the key
    # @param generated_class [Class] the class to cache
    # @return [Class] the inserted class
    def set(descriptor, generated_class)
      @store[descriptor.__id__] = generated_class
    end

    # Returns the cached Generated Class for +descriptor+, or yields to
    # build + cache + return one. The build block is called at most once
    # per descriptor identity per cache.
    #
    # @param descriptor [SerializersCodeGen::Descriptor] the key
    # @yield invoked on cache miss; the return value is cached + returned
    # @yieldreturn [Class] the class to cache for +descriptor+
    # @return [Class] the cached or freshly-built class
    def fetch(descriptor)
      cached = @store[descriptor.__id__]
      return cached if cached
      @store[descriptor.__id__] = yield
    end
  end
end
