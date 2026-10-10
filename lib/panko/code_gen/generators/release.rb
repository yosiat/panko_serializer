# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # A pooled instance that kept +@object+ / +@context+ / +@scope+ after
    # checkin would keep the last record graph alive in fiber-local storage.
    module Release
      module_function

      # Must match the gate in +RecordAccess::Generic.emit_parent_class_ivar_writes+.
      def ivar_writes?(descriptor)
        descriptor.method_attributes.any? { |method_attribute| method_attribute.body.is_a?(Symbol) }
      end

      # Must follow the same edges as {emit} so the answer matches the
      # emitted code.
      def subtree_releases?(descriptor, cyclic_ids, seen = {})
        return false if seen[descriptor.__id__]
        seen[descriptor.__id__] = true
        return true if ivar_writes?(descriptor)
        descriptor.associations.flat_map(&:descriptors).any? do |child|
          next false if child.equal?(descriptor)
          next false if cyclic_ids[descriptor.__id__] && cyclic_ids[child.__id__]
          subtree_releases?(child, cyclic_ids, seen)
        end
      end

      def child_ivars(assoc)
        variants = assoc.variants.each_with_index.map do |variant, index|
          [GeneratedNames.variant_serializer_ivar(assoc, index), variant]
        end
        [[GeneratedNames.serializer_ivar(assoc), assoc.descriptor], *variants]
      end

      # Every class defines +_release+, even an empty one: the serializers call it
      # on every checkin without checking.
      def emit(descriptor, builder, cyclic_ids)
        builder.line "def _release"
        builder.indent do
          if ivar_writes?(descriptor)
            builder.line "@object = nil"
            builder.line "@context = nil"
            builder.line "@scope = nil"
          end
          descriptor.associations.each do |assoc|
            child_ivars(assoc).each do |ivar, child|
              next if child.equal?(descriptor)
              # Ends the chain without per-call visited state; such serializers keep their last record until the next call.
              next if cyclic_ids[descriptor.__id__] && cyclic_ids[child.__id__]
              next unless subtree_releases?(child, cyclic_ids)
              builder.line "#{ivar}._release"
            end
          end
          builder.line "nil"
        end
        builder.line "end"
      end
    end
  end
end
