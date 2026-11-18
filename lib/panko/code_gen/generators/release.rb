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

      def child_ivars(assoc, position)
        variants = assoc.variants.each_with_index.map do |variant, index|
          [GeneratedNames.variant_serializer_ivar(position, index), variant]
        end
        [[GeneratedNames.serializer_ivar(position), assoc.descriptor], *variants]
      end

      # A serializer method's memo lasts one serialize call, as it did when each call built a new
      # serializer. An unset ivar reads as nil, so nil clears it unless a method checks it with
      # +defined?+; those are removed. Nil keeps the instance's shape: removing an ivar and
      # setting it again on the next call costs a shape change each time.
      def emit_serializer_ivar_clears(descriptor, builder)
        written = WrittenIvars.of(descriptor.parent_class)
        return emit_ivar_sweep(descriptor, builder) if written.nil?
        generated = generated_ivars(descriptor)
        written.each do |name, checked|
          next if generated.include?(name)
          builder.line(checked ? "remove_instance_variable(#{name.inspect}) if defined?(#{name})" : "#{name} = nil")
        end
      end

      def emit_ivar_sweep(descriptor, builder)
        builder.line "instance_variables.each do |name|"
        builder.indent do
          builder.line "case name"
          builder.line "when #{generated_ivars(descriptor).map(&:inspect).join(", ")}"
          builder.line "else remove_instance_variable(name)"
          builder.line "end"
        end
        builder.line "end"
      end

      # Must match the ivars +ClassEmitter#emit_initialize+ and the record access code set.
      def generated_ivars(descriptor)
        names = %i[@object @context @scope]
        descriptor.method_attributes.each_with_index do |method_attribute, index|
          names << GeneratedNames.callable_ivar(index).to_sym unless method_attribute.body.is_a?(Symbol)
        end
        descriptor.associations.each_with_index do |assoc, position|
          names << GeneratedNames.if_guard_ivar(position).to_sym if assoc.if
          child_ivars(assoc, position).each { |ivar, _child| names << ivar.to_sym }
        end
        names
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
            emit_serializer_ivar_clears(descriptor, builder)
          end
          descriptor.associations.each_with_index do |assoc, position|
            child_ivars(assoc, position).each do |ivar, child|
              next if child.equal?(descriptor)
              # Ends the chain without per-call visited state; such serializers keep their last record and memos
              # until the next call. Only a hand-built Descriptor can form a cycle: the DSL snapshots each child.
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
