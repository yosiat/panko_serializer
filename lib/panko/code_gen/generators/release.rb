# frozen_string_literal: true

module Panko::CodeGen
  module Generators
    # Emits the +_release+ method every Generated Class carries: the
    # checkin-side counterpart of the per-record +@object+ / +@context+ /
    # +@scope+ writes. A pooled instance that kept those ivars after
    # checkin would pin the last serialized record graph (and
    # request-scoped context) in fiber-local storage until the same
    # (serializer class, mode) serialized again on that fiber — the
    # classic pooled-object leak, and asymmetric with WritersPool, whose
    # checkin resets the Writer. The seam calls +_release+ right before
    # pushing the instance back onto its InstancePool stack.
    #
    # The emitted body is compile-time specialized to do only the work
    # the tree needs: ivar nils only on classes whose +_write_one+ /
    # +_to_hash+ actually writes them (the Symbol-body gate shared with
    # +RecordAccess+), child +_release+ calls only into subtrees that
    # nil something. Classes with nothing to clear still define an empty
    # +_release+ so the seam can call it unconditionally.
    #
    # Recursion contract mirrors the constructor's: a self-loop child
    # (+@x_serializer = self+) is skipped — the receiver's own nils
    # already cover it — and a cyclic child of a cyclic parent is
    # skipped so the chain provably terminates without per-call visited
    # state. Mutual-recursive serializer pairs therefore keep their last
    # record until the next serialize; accepted, since guarding them
    # would cost an allocation or a reset flag on every call for a rare
    # shape.
    module Release
      module_function

      # Whether this class's +_write_one+ / +_to_hash+ writes the
      # per-record ivars — the same gate +RecordAccess+ uses to emit
      # them: only a Symbol-body Method Attribute runs user code on the
      # Generated Class instance.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @return [Boolean]
      def ivar_writes?(descriptor)
        descriptor.method_attributes.any? { |method_attribute| method_attribute.body.is_a?(Symbol) }
      end

      # Whether the emitted +_release+ chain rooted at +descriptor+ nils
      # anything — used to elide child +_release+ calls into subtrees
      # that would be a no-op chain. Follows exactly the edges {emit}
      # follows (self-loops and cyclic-to-cyclic edges excluded), so the
      # answer matches the emitted code.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @param cyclic_ids [Hash{Integer => true}] identity-keyed cyclic set
      # @param seen [Hash{Integer => true}] identity-keyed visited set
      # @return [Boolean]
      def subtree_releases?(descriptor, cyclic_ids, seen = {})
        return false if seen[descriptor.__id__]
        seen[descriptor.__id__] = true
        return true if ivar_writes?(descriptor)
        descriptor.associations.any? do |assoc|
          child = assoc.descriptor
          next false if child.equal?(descriptor)
          next false if cyclic_ids[descriptor.__id__] && cyclic_ids[child.__id__]
          subtree_releases?(child, cyclic_ids, seen)
        end
      end

      # Emits +_release+ for one Generated Class into +builder+.
      #
      # @param descriptor [Panko::CodeGen::Descriptor]
      # @param builder [Panko::CodeGen::CodeBuilder] target buffer
      # @param cyclic_ids [Hash{Integer => true}] identity-keyed cyclic set
      # @return [void]
      def emit(descriptor, builder, cyclic_ids)
        builder.line "def _release"
        builder.indent do
          if ivar_writes?(descriptor)
            builder.line "@object = nil"
            builder.line "@context = nil"
            builder.line "@scope = nil"
          end
          descriptor.associations.each do |assoc|
            child = assoc.descriptor
            next if child.equal?(descriptor)
            next if cyclic_ids[descriptor.__id__] && cyclic_ids[child.__id__]
            next unless subtree_releases?(child, cyclic_ids)
            builder.line "#{GeneratedNames.serializer_ivar(assoc)}._release"
          end
          builder.line "nil"
        end
        builder.line "end"
      end
    end
  end
end
