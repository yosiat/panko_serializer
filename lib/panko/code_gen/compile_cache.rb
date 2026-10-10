# frozen_string_literal: true

module Panko::CodeGen
  # Descriptor -> Generated Class, one entry per unique Descriptor in a tree.
  class CompileCache
    # Keyed by +__id__+, so equal but distinct Descriptors get separate entries.
    def initialize
      @store = {}
    end

    def get(descriptor)
      @store[descriptor.__id__]
    end

    def set(descriptor, generated_class)
      @store[descriptor.__id__] = generated_class
    end

    # The block must call +#set+ before it descends into children, so a recursive
    # call on the same Descriptor hits the entry and the cycle ends.
    def lookup_or_compile(descriptor)
      cached = @store[descriptor.__id__]
      return cached if cached
      yield
      @store[descriptor.__id__]
    end
  end
end
