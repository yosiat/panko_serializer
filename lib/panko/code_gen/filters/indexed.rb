# frozen_string_literal: true

module SerializersCodeGen
  module Filter
    # The +indexed x single_path+ cell — verdict from S13's filter
    # experiment per
    # +docs/research/filter_experiments_results.md § 1+. Lifts
    # +IndexedBitsFilter+ / +IndexedArrayFilter+ /
    # +IndexedFilter.build+ from
    # +docs/research/filter_experiments_bench.rb+ (lines 281–433) into
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
    # code stays monomorphic per +docs/filters.md § Threading through
    # Composition+. The hot-path representation is chosen at construction
    # time and never re-checked per call.
    #
    # +child(<symbol>)+ caches its result keyed by +Source+ symbol (cache
    # lifetime = one +serialize_*+ call — the +Filter+ object is
    # constructed per call and discarded after). For S14.2 the cache
    # always memoizes +Filter::NONE+; threading filters through
    # +Composition+ at nested call sites — and resolving child filters
    # against the nested Generated Class's +FIELD_INDEX+ — lands in
    # S14.4 per the parent S14 PRD scope split.
    module Indexed
      module_function

      # The cutoff between the {Bits} and {Array} representations. At 63
      # the bit-mask is a tagged +Fixnum+ on 64-bit Ruby — one
      # +Integer#[]+ stays constant-time. At 64 the literal would box
      # into a +Bignum+, so +Integer#[]+ on it stops being O(1) and the
      # +Array#[]+ path wins. Per
      # +docs/research/filter_experiments_bench.rb+ comment block at
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
      # +docs/filters.md § Rules+ — caller's may name Fields that have
      # since been removed from the Descriptor without breaking).
      #
      # @param hash [Hash] the caller-supplied non-empty +filters:+ Hash;
      #   +:only+ and +:except+ are read here, other keys are
      #   association sub-filters resolved lazily by {Bits#child} /
      #   {Array#child}
      # @param field_index [Hash{Symbol => Integer}] the
      #   per-Generated-Class +FIELD_INDEX+ map (Field name → declared
      #   index)
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
      # @param name [Symbol] the Field's name
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

        # Returns the cached child filter for +source+. See
        # {Indexed} for the cache-lifetime contract; for S14.2 the cache
        # always memoizes +Filter::NONE+ — the per-source sub-hash is
        # observed but materialization of a real child {Bits} / {Array}
        # against the nested Generated Class's +FIELD_INDEX+ ships in
        # S14.4 with +Composition+ threading.
        #
        # @param source [Symbol] the Association's +Source+
        # @return [Filter::None, Bits, Array]
        def child(source)
          cached = @children_cache[source]
          return cached if cached
          @children_cache[source] = Indexed.resolve_child(@hash, source)
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

        # Returns the cached child filter for +source+. Same
        # cache-lifetime + S14.2-scope contract as {Bits#child}.
        #
        # @param source [Symbol] the Association's +Source+
        # @return [Filter::None, Bits, Array]
        def child(source)
          cached = @children_cache[source]
          return cached if cached
          @children_cache[source] = Indexed.resolve_child(@hash, source)
        end

        # Returns +false+ — see {Bits#none?}.
        #
        # @return [false]
        def none?
          false
        end
      end

      # Resolves the child filter for +source+ given the parent's
      # caller-supplied +hash+. Returns +Filter::NONE+ when the parent
      # hash carries no entry for +source+, when the entry is +nil+,
      # when it is the empty Hash, or when it is non-Hash (the public
      # contract per +docs/filters.md § Public shape+ is that nested
      # values are Hashes — non-Hashes are silently ignored).
      #
      # In S14.2 a non-empty sub-hash also collapses to +Filter::NONE+:
      # materializing a real child Indexed cell needs the nested
      # Generated Class's +FIELD_INDEX+, which only becomes available
      # once +Composition+ threading lands in S14.4. Until then the
      # cache memoizes the {None} singleton so repeated +#child+ calls
      # within one +serialize_*+ call return the same object per the
      # acceptance criterion.
      #
      # @param hash [Hash] the parent's caller-supplied +filters:+ Hash
      # @param source [Symbol] the Association's +Source+
      # @return [Filter::None]
      def resolve_child(hash, source)
        sub = hash[source]
        return NONE unless sub.is_a?(Hash) && !sub.empty?
        # TODO(S14.4): build a real child Bits/Array against the nested
        # Generated Class's FIELD_INDEX once Composition threading wires
        # filters.child(:source) at nested call sites.
        NONE
      end
    end
  end
end
