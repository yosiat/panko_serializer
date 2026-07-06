# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Shared Descriptor-tree traversal used by per-mode emitters
    # (+JsonMode+, +HashMode+) to decide what classes to emit and in
    # what order. Identity-keyed (+__id__+) per
    # +docs/descriptor.md § Recursive Descriptors+ — a shared inner
    # Descriptor (and, in S8, a recursive one) is visited exactly once.
    module DescriptorWalk
      module_function

      # Returns the unique Descriptors reachable from +root+ in
      # post-order (children before parents) so each parent class
      # definition references already-defined nested classes.
      #
      # @param root [Panko::CodeGen::Descriptor]
      # @return [Array<Panko::CodeGen::Descriptor>] post-order list
      def in_emit_order(root)
        order = []
        visit(root, order, {})
        order
      end

      # Depth-first identity-keyed visit appending in post-order. Private
      # to the +in_emit_order+ implementation; module-functioned only so
      # the recursion can call back without an instance.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @param order [Array<Panko::CodeGen::Descriptor>] output buffer
      # @param seen [Hash{Integer => true}] identity-key visited set
      # @return [void]
      def visit(descriptor, order, seen)
        return if seen[descriptor.__id__]
        seen[descriptor.__id__] = true
        descriptor.associations.each { |assoc| visit(assoc.descriptor, order, seen) }
        order << descriptor
      end
    end
  end
end
