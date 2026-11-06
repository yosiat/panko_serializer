# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Only cycles of two or more need +_construct_cache:+; a self-loop uses +@<name>_serializer = self+.
    # Tarjan's SCC: a DFS that skips finished nodes misses Y in A -> X -> A plus A -> Y -> X -> A.
    module CycleMembership
      module_function

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

      # +next_index+ is a one-element Array so recursive calls share the counter.
      def strongconnect(v, cyclic, index, lowlink, on_stack, scc_stack, next_index)
        vid = v.__id__
        index[vid] = next_index[0]
        lowlink[vid] = next_index[0]
        next_index[0] += 1
        scc_stack.push(v)
        on_stack[vid] = true

        v.associations.flat_map(&:descriptors).each do |w|
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
