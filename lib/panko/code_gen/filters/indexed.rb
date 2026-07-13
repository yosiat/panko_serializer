# frozen_string_literal: true

module Panko::CodeGen
  module Filter
    # The +indexed x single_path+ cell — verdict from S13's filter
    # experiment per
    # +docs/code_gen/research/filter_experiments_results.md § 1+. Lifts
    # +IndexedBitsFilter+ / +IndexedArrayFilter+ /
    # +IndexedFilter.build+ from
    # +docs/code_gen/research/filter_experiments_bench.rb+ (lines 281–433) into
    # production code.
    #
    # The constructor inspects the per-Generated-Class +FIELD_INDEX+
    # (built by {Generators::FieldIndex} and emitted as a frozen constant
    # on every Generated Class) and picks one of two representations:
    #
    # - {Bits} — single +Integer+ bit-mask, used when +FIELD_INDEX.size+
    #   is +<= INDEXED_BITS_THRESHOLD+. +#drops?+ is +Integer#[]+ — one
    #   bitwise extraction with no Bignum boxing on 64-bit Ruby.
    # - {Array} — Boolean +Array+, used otherwise. +#drops?+ is
    #   +Array#[]+ — one indexed load.
    #
    # Both representations satisfy the same +drops?(<integer>)+ /
    # +child(<symbol>)+ / +none?+ contract as +Filter::NONE+ so emitted
    # code stays monomorphic per +docs/code_gen/filters.md § Threading through
    # Composition+. The hot-path representation is chosen at construction
    # time and never re-checked per call.
    #
    # +child(<symbol>, <field_index>)+ caches its result keyed by +Source+
    # symbol (cache lifetime = one +serialize_*+ call — the +Filter+ object
    # is constructed per call and discarded after). The nested Generated
    # Class's +FIELD_INDEX+ is passed at the call site by the parent's
    # emitted code (the parent statically knows the child class's
    # +FIELD_INDEX+ constant via +Composition+); the child cell is built
    # against it and memoized for the remainder of the +serialize_*+ call.
    # When the parent's caller-supplied +Hash+ has no entry for +source+,
    # an empty sub-+Hash+, or a non-+Hash+ value, the cache memoizes the
    # {Filter::NONE} singleton instead per
    # +docs/code_gen/filters.md § Public shape+.
    module Indexed
      module_function

      # The cutoff between the {Bits} and {Array} representations. At 63
      # the bit-mask is a tagged +Fixnum+ on 64-bit Ruby — one
      # +Integer#[]+ stays constant-time. At 64 the literal would box
      # into a +Bignum+, so +Integer#[]+ on it stops being O(1) and the
      # +Array#[]+ path wins. Per
      # +docs/code_gen/research/filter_experiments_bench.rb+ comment block at
      # lines 336–339.
      INDEXED_BITS_THRESHOLD = 63

      # Builds the appropriate {Bits} or {Array} filter for +hash+
      # against the given +field_index+. Walks +field_index+ once at
      # construction to translate the caller-supplied +:only+ / +:except+
      # symbol lists into the per-representation drops storage; the hot
      # +#drops?+ path then never touches +field_index+ or +hash+
      # again.
      #
      # Names in +:only+ / +:except+ that are not present in
      # +field_index+ are silently ignored (forward-compatibility per
      # +docs/code_gen/filters.md § Rules+ — caller's may name Fields that have
      # since been removed from the Descriptor without breaking).
      #
      # @param hash [Hash] the caller-supplied non-empty +filters:+ Hash;
      #   +:only+ and +:except+ are read here, other keys are
      #   association sub-filters resolved lazily by {Bits#child} /
      #   {Array#child}
      # @param field_index [Hash{Symbol => Integer}] the
      #   per-Generated-Class +FIELD_INDEX+ map (filter key → declared
      #   index; value Fields key by +name+, Associations by +source+
      #   — see {Generators::FieldIndex.build})
      # @return [Bits, Array] the bit-mask cell when
      #   +field_index.size <= INDEXED_BITS_THRESHOLD+, the boolean-array
      #   cell otherwise
      def build(hash, field_index)
        n = field_index.size
        only = hash[:only]
        except = hash[:except]
        only_set = only&.to_set
        except_set = except&.to_set

        if n <= INDEXED_BITS_THRESHOLD
          mask = 0
          field_index.each do |name, i|
            mask |= (1 << i) if drop?(name, only_set, except_set)
          end
          Bits.new(hash, mask)
        else
          arr = ::Array.new(n)
          field_index.each do |name, i|
            arr[i] = drop?(name, only_set, except_set)
          end
          Array.new(hash, arr)
        end
      end

      # Returns whether +name+ should be dropped given the resolved
      # +only_set+ / +except_set+. +:only+ wins over +:except+ when
      # both are present (the +:only+/+:except+ co-supplied check is
      # S14.3 — until then the +:only+ branch takes precedence and the
      # +:except+ Set is ignored).
      #
      # @param name [Symbol] the Field's +FIELD_INDEX+ key (+name+ for
      #   value Fields, +source+ for Associations)
      # @param only_set [Set<Symbol>, nil] resolved +:only+ list as a
      #   +Set+, or +nil+ when not supplied
      # @param except_set [Set<Symbol>, nil] resolved +:except+ list
      # @return [Boolean]
      def drop?(name, only_set, except_set)
        if only_set
          !only_set.include?(name)
        elsif except_set
          except_set.include?(name)
        else
          false
        end
      end

      # Bit-mask representation. Drops storage is a single +Integer+
      # whose +i+'th bit is set when the Field at index +i+ should be
      # dropped. +#drops?+ is +@drops_mask[index]+ — one +Integer#[]+
      # extraction returning +0+ or +1+ on a tagged +Fixnum+, no
      # allocations on the hot path.
      class Bits
        # @param hash [Hash] the caller-supplied +filters:+ Hash, kept
        #   for lazy {#child} resolution against association sub-hashes
        # @param drops_mask [Integer] precomputed bit-mask where bit +i+
        #   is set iff the Field at index +i+ is filtered out
        def initialize(hash, drops_mask)
          @hash = hash
          @drops_mask = drops_mask
          @children_cache = {}
        end

        # Returns +true+ when the Field at +index+ is filtered out.
        # Constant-time: one +Integer#[]+ bit extraction, comparing to
        # +1+ to coerce the +0+/+1+ result into a Boolean.
        #
        # @param index [Integer] the Field's codegen-time +FIELD_INDEX+
        #   position
        # @return [Boolean]
        def drops?(index)
          @drops_mask[index] == 1
        end

        # Returns the cached child filter for +source+ scoped against the
        # nested Generated Class's +field_index+. See {Indexed} for the
        # cache-lifetime contract: the resolved child is memoized for the
        # remainder of the parent's +serialize_*+ call so a +has_many+
        # iteration consults the cache once at hoist time and never
        # rebuilds. Per +docs/code_gen/filters.md § Threading through Composition+
        # the parent's emitted code passes the child class's +FIELD_INDEX+
        # constant at the call site.
        #
        # The cached pair carries the +field_index+ the cell was built
        # against, guarded by +equal?+: two Associations may share one
        # +Source+ while nesting different child classes, and a cell
        # built against the first child's +FIELD_INDEX+ would drop the
        # wrong positions in the second. The common case (one child class
        # per Source) still hits the memo with zero allocations —
        # +FIELD_INDEX+ constants are stable objects.
        #
        # @param source [Symbol] the Association's +Source+
        # @param field_index [Hash{Symbol => Integer}] the nested Generated
        #   Class's +FIELD_INDEX+ — required when the parent's
        #   caller-supplied sub-+Hash+ for +source+ is non-empty
        # @return [Filter::None, Bits, Array]
        def child(source, field_index)
          cached = @children_cache[source]
          return cached[1] if cached && cached[0].equal?(field_index)
          resolved = Indexed.resolve_child(@hash, source, field_index)
          @children_cache[source] = [field_index, resolved]
          resolved
        end

        # Returns +false+ — every Indexed cell carries at least one
        # filter rule (or it would have collapsed to {Filter::NONE} in
        # {Filter.wrap}).
        #
        # @return [false]
        def none?
          false
        end
      end

      # Boolean-Array representation. Drops storage is an +Array+ of
      # +true+ / +false+ at each Field's index position. +#drops?+ is
      # +@drops_array[index]+ — one indexed load, no bit math.
      class Array
        # @param hash [Hash] the caller-supplied +filters:+ Hash, kept
        #   for lazy {#child} resolution against association sub-hashes
        # @param drops_array [::Array<Boolean>] precomputed Boolean
        #   Array where +drops_array[i]+ is +true+ iff the Field at
        #   index +i+ is filtered out
        def initialize(hash, drops_array)
          @hash = hash
          @drops_array = drops_array
          @children_cache = {}
        end

        # Returns +true+ when the Field at +index+ is filtered out.
        # Constant-time: one +Array#[]+ load.
        #
        # @param index [Integer] the Field's codegen-time +FIELD_INDEX+
        #   position
        # @return [Boolean]
        def drops?(index)
          @drops_array[index]
        end

        # Returns the cached child filter for +source+ scoped against the
        # nested Generated Class's +field_index+. Same cache-lifetime,
        # +Composition+-threading, and per-child-+FIELD_INDEX+ scoping
        # contract as {Bits#child}.
        #
        # @param source [Symbol] the Association's +Source+
        # @param field_index [Hash{Symbol => Integer}] the nested Generated
        #   Class's +FIELD_INDEX+
        # @return [Filter::None, Bits, Array]
        def child(source, field_index)
          cached = @children_cache[source]
          return cached[1] if cached && cached[0].equal?(field_index)
          resolved = Indexed.resolve_child(@hash, source, field_index)
          @children_cache[source] = [field_index, resolved]
          resolved
        end

        # Returns +false+ — see {Bits#none?}.
        #
        # @return [false]
        def none?
          false
        end
      end

      # Resolves the child filter for +source+ given the parent's
      # caller-supplied +hash+ and the nested Generated Class's
      # +field_index+. Returns +Filter::NONE+ when the parent hash carries
      # no entry for +source+, when the entry is +nil+, when it is the
      # empty Hash, or when it is non-Hash (the public contract per
      # +docs/code_gen/filters.md § Public shape+ is that nested values are Hashes
      # — non-Hashes are silently ignored).
      #
      # When the sub-hash is a non-empty +Hash+, builds a real child
      # {Bits} / {Array} cell directly via {build} — co-supply validation
      # (per +docs/code_gen/filters.md § Rules+) already ran at the top-level
      # +Filter.wrap+ call and walked every nested level depth-first, so
      # this resolution path can skip re-validating and pay only the
      # one-shot index walk that {build} performs against +field_index+.
      #
      # @param hash [Hash] the parent's caller-supplied +filters:+ Hash
      # @param source [Symbol] the Association's +Source+
      # @param field_index [Hash{Symbol => Integer}] the nested Generated
      #   Class's +FIELD_INDEX+ — required when +hash[source]+ is a
      #   non-empty +Hash+
      # @return [Filter::None, Bits, Array]
      def resolve_child(hash, source, field_index)
        sub = hash[source]
        return NONE unless sub.is_a?(Hash) && !sub.empty?
        build(sub, field_index)
      end
    end
  end
end
