# frozen_string_literal: true

require_relative "../code_gen"

module Panko
  module CodeGen
    # Adapter that converts a +Panko::SerializationDescriptor+ (the class-time
    # DSL accumulation, backed by the C extension) into the immutable
    # +Panko::CodeGen::Descriptor+ the engine compiles.
    #
    # Two invariants come from the merge plan (docs/merging-into-panko.md):
    #
    # - +models: nil+ always. Panko's DSL never declares the record class, so
    #   the engine runs on the generic path (see § AR scope).
    # - +parent_class:+ is the user's serializer class, so method fields
    #   dispatch as Symbol bodies directly on +self+ and +#object+/+#context+/
    #   +#scope+ resolve against the ivars the generated +_write_one+ sets
    #   (see § Generated Class subclasses the user's Panko serializer).
    #
    # The converter is filter-agnostic: filters translate to a runtime
    # +Filter+ elsewhere (Q8/Q9), never into the compiled descriptor.
    module DescriptorBuilder
      module_function

      # @param panko_desc [Panko::SerializationDescriptor] the class descriptor
      # @param path [Hash] internal DFS guard keyed by descriptor object id
      # @return [Panko::CodeGen::Descriptor]
      def from_panko_descriptor(panko_desc, path = {})
        oid = panko_desc.object_id
        # Panko builds a fresh (finite) descriptor per association, so this only
        # trips on a genuine cycle — surfaced loudly rather than as a stack overflow.
        raise DescriptorError, "cyclic Panko descriptor for #{panko_desc.type}" if path[oid]
        path[oid] = true

        type = panko_desc.type
        Descriptor.new(
          name: descriptor_name(type),
          models: nil,
          attributes: panko_desc.attributes.map { |attr| build_attribute(attr) },
          method_attributes: panko_desc.method_fields.map { |field| build_method_attribute(field) },
          associations: build_associations(panko_desc, path),
          parent_class: type
        )
      ensure
        path.delete(oid)
      end

      # Panko's +alias_name+ is the output key override; its +name+ is the
      # record method. Maps to the engine's +name+ (output) / +source+ (reader).
      def build_attribute(panko_attr)
        Attribute.new(name: output_key(panko_attr), source: panko_attr.name.to_sym)
      end

      # A method field dispatches to a same-named method on the serializer, so
      # the body is the method Symbol; +alias_name+ still overrides the output key.
      def build_method_attribute(panko_attr)
        MethodAttribute.new(name: output_key(panko_attr), body: panko_attr.name.to_sym)
      end

      def build_associations(panko_desc, path)
        panko_desc.has_one_associations.map { |assoc| build_association(assoc, :has_one, path) } +
          panko_desc.has_many_associations.map { |assoc| build_association(assoc, :has_many, path) }
      end

      # +name_str+ is the output key (Panko's +options[:name]+ or the reader
      # name); +name_sym+ is the reader Panko calls on the record. This is the
      # axis Panko and the engine disagree on — do not swap them.
      def build_association(panko_assoc, kind, path)
        Association.new(
          name: panko_assoc.name_str.to_sym,
          kind: kind,
          descriptor: from_panko_descriptor(panko_assoc.descriptor, path),
          source: panko_assoc.name_sym
        )
      end

      def output_key(panko_attr)
        (panko_attr.alias_name || panko_attr.name).to_sym
      end

      # Anonymous serializers still need a unique, valid generated-class stem.
      def descriptor_name(type)
        type.name || "PankoSerializer#{type.object_id}"
      end
    end
  end
end
