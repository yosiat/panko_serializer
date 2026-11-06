# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    module DescriptorWalk
      module_function

      def in_emit_order(root)
        order = []
        visit(root, order, {})
        order
      end

      def visit(descriptor, order, seen)
        return if seen[descriptor.__id__]
        seen[descriptor.__id__] = true
        descriptor.associations.each { |assoc| assoc.descriptors.each { |child| visit(child, order, seen) } }
        order << descriptor
      end
    end
  end
end
