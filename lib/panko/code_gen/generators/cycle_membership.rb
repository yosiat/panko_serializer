# frozen_string_literal: true

module SerializersCodeGen
  module Generators
    # Identity-keyed cycle-membership analysis on a Descriptor tree:
    # returns the set of Descriptor +__id__+s that participate in a
    # mutual-recursion cycle reachable from a given root. Used by the
    # per-mode emitters to decide which Generated Classes need the
    # +_construct_cache:+ kwarg + cache-threaded nested +.new+ calls
    # per +docs/compilation.md § Recursive Descriptors+ (S8.2).
    #
    # "Mutual recursion" here means a cycle of length ≥ 2 — a Descriptor
    # is reachable from itself via a path that traverses at least one
    # other Descriptor. Length-1 self-loops (Comment +has_many :replies+
    # → Comment) are deliberately excluded: they are handled by the
    # +@<name>_serializer = self+ shortcut emitted at the per-Association
    # level (S8.1), which carries no cache and no extra allocation.
    # Marking self-loops as "cyclic" would force a +_construct_cache+
    # kwarg + Hash allocation onto every self-recursive constructor with
    # no behavioral benefit — the += self+ shortcut already breaks the
    # otherwise-infinite +.new+ chain.
    module CycleMembership
      module_function

      # Walks the Descriptor tree depth-first from +root+ and returns a
      # +Hash{Integer => true}+ keyed by +descriptor.__id__+ for every
      # Descriptor that participates in a mutual-recursion cycle (length
      # ≥ 2). Acyclic Descriptors and Descriptors that participate only
      # in length-1 self-loops are absent from the returned Hash.
      #
      # The walk uses the standard "white/grey/black" cycle-detection
      # shape: each Descriptor is +in_stack+ while its DFS subtree is
      # being processed; a back-edge to a +in_stack+ ancestor marks
      # every Descriptor on the cycle path as cyclic. Self-edges
      # (+a.descriptor.equal?(d)+) are skipped before the recursive
      # call so they can't trigger the back-edge branch.
      #
      # @param root [SerializersCodeGen::Descriptor] the tree root
      # @return [Hash{Integer => true}] identity-keyed set of cyclic
      #   Descriptor +__id__+s; empty Hash when the tree is acyclic
      def cyclic_descriptor_ids(root)
        cyclic = {}
        in_stack = {}
        stack = []
        visited = {}
        walk(root, cyclic, in_stack, stack, visited)
        cyclic
      end

      # Recursive worker for {.cyclic_descriptor_ids}. Pushes +d+ onto
      # the +in_stack+ before iterating its Associations + recursing,
      # pops on the way out. Self-loop edges are skipped so a
      # length-1 self-cycle is not flagged. A non-self back-edge to an
      # +in_stack+ ancestor marks every Descriptor between that
      # ancestor (inclusive) and +d+ (inclusive) as cyclic.
      #
      # @param d [SerializersCodeGen::Descriptor] the current node
      # @param cyclic [Hash{Integer => true}] accumulator output
      # @param in_stack [Hash{Integer => Integer}] +__id__+ → stack
      #   index for ancestors of the current DFS path
      # @param stack [Array<SerializersCodeGen::Descriptor>] ordered
      #   ancestors on the current DFS path
      # @param visited [Hash{Integer => true}] fully-processed
      #   Descriptor +__id__+s — short-circuits re-walks of acyclic
      #   subtrees + acyclic-children-of-cyclic subtrees
      # @return [void]
      def walk(d, cyclic, in_stack, stack, visited)
        return if visited[d.__id__]
        if (idx = in_stack[d.__id__])
          stack[idx..].each { |c| cyclic[c.__id__] = true }
          return
        end
        in_stack[d.__id__] = stack.length
        stack.push(d)
        d.associations.each do |a|
          next if a.descriptor.equal?(d)
          walk(a.descriptor, cyclic, in_stack, stack, visited)
        end
        stack.pop
        in_stack.delete(d.__id__)
        visited[d.__id__] = true
      end
    end
  end
end
