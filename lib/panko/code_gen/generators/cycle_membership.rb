# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Identity-keyed cycle-membership analysis on a Descriptor tree:
    # returns the set of Descriptor +__id__+s that participate in a
    # mutual-recursion cycle reachable from a given root. Used by the
    # per-mode emitters to decide which Generated Classes need the
    # +_construct_cache:+ kwarg + cache-threaded nested +.new+ calls
    # per +docs/code_gen/compilation.md § Recursive Descriptors+ (S8.2).
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
    #
    # Implementation is Tarjan's strongly-connected-components algorithm.
    # A Descriptor is cyclic iff it belongs to an SCC of size ≥ 2; size-1
    # SCCs are acyclic (the only length-1-cycle case is a self-loop, and
    # self-edges are filtered out before the SCC analysis). Tarjan's
    # correctly handles graphs where multiple paths reach the same
    # back-edge — a simpler DFS that short-circuits already-finished
    # nodes would miss "shortcut" cycles like A → X → A *and*
    # A → Y → X → A (Y is on the larger cycle but is reached only after
    # X is finished, so the back-edge through X is no longer on the
    # ancestor stack).
    module CycleMembership
      module_function

      # Walks the Descriptor tree depth-first from +root+ and returns a
      # +Hash{Integer => true}+ keyed by +descriptor.__id__+ for every
      # Descriptor that participates in a mutual-recursion cycle (length
      # ≥ 2). Acyclic Descriptors and Descriptors that participate only
      # in length-1 self-loops are absent from the returned Hash.
      #
      # @param root [Panko::CodeGen::Descriptor] the tree root
      # @return [Hash{Integer => true}] identity-keyed set of cyclic
      #   Descriptor +__id__+s; empty Hash when the tree is acyclic
      def cyclic_descriptor_ids(root)
        cyclic = {}
        index = {}
        lowlink = {}
        on_stack = {}
        scc_stack = []
        next_index = [0]
        strongconnect(root, cyclic, index, lowlink, on_stack, scc_stack, next_index)
        cyclic
      end

      # Recursive worker for {.cyclic_descriptor_ids} — one node-visit
      # of Tarjan's SCC algorithm. Assigns +v+ a discovery index +
      # initial lowlink, pushes onto the SCC stack, then iterates
      # outgoing Associations: for unvisited targets, recurses + folds
      # the child's lowlink into +v+'s; for stack-resident targets,
      # folds the target's discovery index into +v+'s lowlink (the
      # back-edge case). Self-edges are skipped before this dispatch
      # so a length-1 self-loop is not flagged. When +v+'s lowlink
      # equals its index, +v+ is the root of an SCC — pop the SCC off
      # the stack; if its size is ≥ 2 (mutual cycle), mark every
      # member as cyclic.
      #
      # @param v [Panko::CodeGen::Descriptor] the current node
      # @param cyclic [Hash{Integer => true}] accumulator output
      # @param index [Hash{Integer => Integer}] per-node discovery index
      # @param lowlink [Hash{Integer => Integer}] per-node lowlink
      # @param on_stack [Hash{Integer => true}] currently-on-SCC-stack flag
      # @param scc_stack [Array<Panko::CodeGen::Descriptor>] SCC stack
      # @param next_index [Array<Integer>] single-element box holding the
      #   monotonically-increasing discovery counter (boxed so recursive
      #   frames share state)
      # @return [void]
      def strongconnect(v, cyclic, index, lowlink, on_stack, scc_stack, next_index)
        vid = v.__id__
        index[vid] = next_index[0]
        lowlink[vid] = next_index[0]
        next_index[0] += 1
        scc_stack.push(v)
        on_stack[vid] = true

        v.associations.each do |a|
          w = a.descriptor
          next if w.equal?(v)
          wid = w.__id__
          if !index.key?(wid)
            strongconnect(w, cyclic, index, lowlink, on_stack, scc_stack, next_index)
            lowlink[vid] = lowlink[wid] if lowlink[wid] < lowlink[vid]
          elsif on_stack[wid]
            lowlink[vid] = index[wid] if index[wid] < lowlink[vid]
          end
        end

        return unless lowlink[vid] == index[vid]
        scc = []
        loop do
          w = scc_stack.pop
          on_stack.delete(w.__id__)
          scc << w
          break if w.equal?(v)
        end
        scc.each { |w| cyclic[w.__id__] = true } if scc.size > 1
      end
    end
  end
end
