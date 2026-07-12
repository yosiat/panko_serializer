# frozen_string_literal: true

module Panko::CodeGen
  # Identity-keyed map of Descriptor → Generated Class, threaded through
  # +Compiler+'s recursive descent so each unique Descriptor in a tree
  # produces exactly one Generated Class (per
  # +docs/code_gen/compilation.md § Recursive Descriptors+).
  #
  # Two block forms are exposed: +#fetch+ for the common one-shot
  # "compute-and-cache" pattern (block return value is what gets cached),
  # and +#lookup_or_compile+ for the recursive pattern where the block
  # must surface its in-progress class to a back-edge lookup *before*
  # descending into children — see +#lookup_or_compile+ for the contract.
  # The recursive form is what unblocks self-referential and mutually
  # recursive Descriptor trees per +docs/code_gen/compilation.md § Recursive
  # Descriptors+.
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
    # @param descriptor [Panko::CodeGen::Descriptor] the lookup key
    # @return [Class, nil] the cached class, or +nil+ on miss
    def get(descriptor)
      @store[descriptor.__id__]
    end

    # Inserts +generated_class+ under +descriptor+'s identity. Returns
    # the inserted class so callers can chain +cache.set(d, klass)+.
    #
    # @param descriptor [Panko::CodeGen::Descriptor] the key
    # @param generated_class [Class] the class to cache
    # @return [Class] the inserted class
    def set(descriptor, generated_class)
      @store[descriptor.__id__] = generated_class
    end

    # Returns the cached Generated Class for +descriptor+, or yields to
    # build + cache + return one. The build block is called at most once
    # per descriptor identity per cache.
    #
    # @param descriptor [Panko::CodeGen::Descriptor] the key
    # @yield invoked on cache miss; the return value is cached + returned
    # @yieldreturn [Class] the class to cache for +descriptor+
    # @return [Class] the cached or freshly-built class
    def fetch(descriptor)
      cached = @store[descriptor.__id__]
      return cached if cached
      @store[descriptor.__id__] = yield
    end

    # Recursive-descent variant of +#fetch+. Returns the cached Generated
    # Class for +descriptor+ on hit; otherwise yields once and returns
    # whatever the block populated under +descriptor.__id__+ via +#set+.
    # The contract differs from +#fetch+ in *when* the cache entry
    # becomes visible to recursive callers:
    #
    # - +#fetch+ caches the block's return value *after* the block has
    #   finished. A recursive +#fetch(same_descriptor)+ inside the block
    #   misses, re-enters, and infinite-loops on cycles.
    # - +#lookup_or_compile+ requires the block itself to call
    #   +#set(descriptor, klass)+ *before* descending into children. A
    #   recursive +#lookup_or_compile(same_descriptor)+ then hits the
    #   in-progress entry and returns the back-edge reference, breaking
    #   the cycle without infinite descent.
    #
    # Used by +Compiler#cache_descendants+ to walk the post-eval
    # Descriptor tree and populate the cache with one Generated Class
    # per unique Descriptor — including self-references (Comment
    # +has_many :replies+ → Comment) and mutual-recursion cycles
    # (Folder → Item → Folder, S8.2). The post-eval class lookup happens
    # before any recursive descent, so the cache is populated in
    # parent-first order and back-edges find their target on the first
    # +#get+.
    #
    # @param descriptor [Panko::CodeGen::Descriptor] the key
    # @yield invoked on cache miss; expected to call
    #   +#set(descriptor, klass)+ on +self+ before any recursive
    #   +#lookup_or_compile+ on +descriptor+ identity
    # @yieldreturn [void] the block's return value is discarded; the
    #   cache entry is read back via +#get+ after the block returns
    # @return [Class, nil] the cached or freshly-built class — read out
    #   of the cache after the block returns, so omitting the +#set+
    #   inside the block returns +nil+
    def lookup_or_compile(descriptor)
      cached = @store[descriptor.__id__]
      return cached if cached
      yield
      @store[descriptor.__id__]
    end
  end
end
