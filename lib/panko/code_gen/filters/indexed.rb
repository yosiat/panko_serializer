# frozen_string_literal: true

module Panko::CodeGen
  module Filter
    # The one indexed cell. Drops storage is a Boolean +Array+ indexed
    # by the position each Field holds in the per-Generated-Class
    # +FIELD_INDEX+ (built by {Generators::FieldIndex} and emitted as a
    # frozen constant on every Generated Class). +#drops?+ is
    # +Array#[]+, one indexed load.
    #
    # {Array} satisfies the same +drops?(<integer>)+ /
    # +child(<symbol>)+ contract as +Filter::None+ so emitted
    # code stays monomorphic.
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
    # {Filter::None} singleton instead.
    module Indexed
      module_function

      # Builds the {Array} filter for +hash+ against the given
      # +field_index+. Walks +field_index+ once at construction to
      # translate the caller-supplied +:only+ / +:except+ symbol lists
      # into the drops storage; the hot +#drops?+ path then never
      # touches +field_index+ or +hash+ again.
      #
      # Names in +:only+ / +:except+ that are not present in
      # +field_index+ are silently ignored (forward-compatibility —
      # caller's may name Fields that have since been removed from the
      # Descriptor without breaking).
      #
      # @param hash [Hash] the caller-supplied non-empty +filters:+ Hash;
      #   +:only+ and +:except+ are read here, other keys are
      #   association sub-filters resolved lazily by {Array#child}
      # @param field_index [Hash{Symbol => Integer}] the
      #   per-Generated-Class +FIELD_INDEX+ map (filter key → declared
      #   index; value Fields key by +name+, Associations by +source+
      #   — see {Generators::FieldIndex.build})
      # @return [Array] the indexed cell
      def build(hash, field_index)
        n = field_index.size
        only = hash[:only]
        except = hash[:except]
        only_set = only&.to_set
        except_set = except&.to_set

        arr = ::Array.new(n)
        field_index.each do |name, i|
          arr[i] = drop?(name, only_set, except_set)
        end
        Array.new(hash, arr)
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

      # Boolean-Array representation. Drops storage is an +Array+ of
      # +true+ / +false+ at each Field's index position. +#drops?+ is
      # +@drops_array[index]+ — one indexed load.
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
        # nested Generated Class's +field_index+. See {Indexed} for the
        # cache-lifetime contract: the resolved child is memoized for the
        # remainder of the parent's +serialize_*+ call so a +has_many+
        # iteration consults the cache once at hoist time and never
        # rebuilds. The parent's emitted code passes the child class's
        # +FIELD_INDEX+ constant at the call site.
        #
        # The cached pair carries the +field_index+ the cell was built
        # against, guarded by +equal?+: two Associations may share one
        # +Source+ while nesting different child classes, and a cell
        # built against the first child's +FIELD_INDEX+ would drop the
        # wrong positions in the second. The common case (one child class
        # per Source) still hits the memo with zero allocations -
        # +FIELD_INDEX+ constants are stable objects.
        #
        # @param source [Symbol] the Association's +Source+
        # @param field_index [Hash{Symbol => Integer}] the nested Generated
        #   Class's +FIELD_INDEX+
        # @return [Filter::None, Array]
        def child(source, field_index)
          cached = @children_cache[source]
          return cached[1] if cached && cached[0].equal?(field_index)
          resolved = Indexed.resolve_child(@hash, source, field_index)
          @children_cache[source] = [field_index, resolved]
          resolved
        end
      end

      # Resolves the child filter for +source+ given the parent's
      # caller-supplied +hash+ and the nested Generated Class's
      # +field_index+. Returns +Filter::None+ when the parent hash carries
      # no entry for +source+, when the entry is +nil+, when it is the
      # empty Hash, or when it is non-Hash (the public contract is that
      # nested values are Hashes — non-Hashes are silently ignored).
      #
      # When the sub-hash is a non-empty +Hash+, builds a real child
      # {Array} cell directly via {build} — co-supply validation
      # already ran at the top-level
      # +Filter.wrap+ call and walked every nested level depth-first, so
      # this resolution path can skip re-validating and pay only the
      # one-shot index walk that {build} performs against +field_index+.
      #
      # @param hash [Hash] the parent's caller-supplied +filters:+ Hash
      # @param source [Symbol] the Association's +Source+
      # @param field_index [Hash{Symbol => Integer}] the nested Generated
      #   Class's +FIELD_INDEX+ — required when +hash[source]+ is a
      #   non-empty +Hash+
      # @return [Filter::None, Array]
      def resolve_child(hash, source, field_index)
        sub = hash[source]
        return None unless sub.is_a?(Hash) && !sub.empty?
        build(sub, field_index)
      end
    end
  end
end
