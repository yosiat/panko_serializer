# frozen_string_literal: true

require_relative "../code_gen"
require_relative "filter_adapter"

module Panko
  module CodeGen
    # Assembles an immutable +Panko::CodeGen::Descriptor+ from a
    # +Panko::Serializer+ class's accumulated DSL declarations (its
    # +_cg_attributes+ / +_cg_method_attributes+ / +_cg_associations+). The DSL
    # already stores Fields as the engine's own +Attribute+ / +MethodAttribute+
    # value objects and builds each Association's nested Descriptor eagerly when
    # the association is declared (see +Panko::Serializer.has_one+/+has_many+),
    # snapshotting the target serializer as it stands then — matching Panko's
    # finite, one-level self-recursion — so this assembly never recurses.
    module DescriptorBuilder
      module_function

      # @param serializer_class [Class] a Panko::Serializer subclass
      # @return [Panko::CodeGen::Descriptor]
      def build(serializer_class)
        Descriptor.new(
          name: descriptor_name(serializer_class),
          model: serializer_class._cg_model,
          attributes: serializer_class._cg_attributes.dup,
          method_attributes: serializer_class._cg_method_attributes.dup,
          associations: serializer_class._cg_associations.map { |decl| to_association(decl) },
          parent_class: serializer_class
        )
      end

      # Anonymous serializers still need a unique, valid generated-class stem.
      def descriptor_name(serializer_class)
        serializer_class.name || "PankoSerializer#{serializer_class.object_id}"
      end

      # Rebuilds the tree so every Descriptor has a unique +name+. Panko snapshots
      # a self-referential association one level deep (a distinct Descriptor of
      # the same serializer class as its parent), so two Descriptors can share a
      # name — and the engine emits one Generated Class per Descriptor, keyed on
      # +name+, so a shared name reopens the same class and corrupts it. Walks
      # post-order (children first) and suffixes the 2nd+ occurrence of each name.
      def uniquify_names(descriptor, seen = Hash.new(0))
        associations = descriptor.associations.map do |association|
          association.with(descriptor: uniquify_names(association.descriptor, seen))
        end
        seen[descriptor.name] += 1
        count = seen[descriptor.name]
        name = (count == 1) ? descriptor.name : "#{descriptor.name}_#{count}"
        descriptor.with(name: name, associations: associations)
      end

      # Narrows a nested Descriptor by a statically-declared association filter
      # (+has_many :x, only: [...]+ / +except: [...]+). Reuses {FilterAdapter} to
      # normalize Panko's filter shape, then drops the Fields the engine Filter
      # would drop — baking the static filter into the cached Descriptor.
      def narrow(descriptor, only, except)
        return descriptor if blank?(only) && blank?(except)
        narrow_by(descriptor, FilterAdapter.to_engine_filters(only, except))
      end

      # Rebuilds +descriptor+ with +model+ as its Model and, recursively, each
      # association's reflected AR class as the child's Model — the
      # auto-specialization tree fill (SerializerCache.variant_pool). A child
      # Descriptor is left untouched when it declared its own Model, when the
      # association source is not an AR reflection on the parent Model (plain
      # method source), when the reflection is polymorphic or its class
      # unresolvable, or when the reflected class is anonymous or not AR-like
      # — all cases where no single Model can be promised at compile time; the
      # child stays on the Generic path and per-record guards keep the tree
      # safe regardless.
      #
      # +seen+ breaks cycles defensively: Panko-built trees are acyclic (a
      # self-referential association snapshots one level deep), but the engine
      # accepts cyclic graphs, and a revisited Descriptor is returned
      # unspecialized rather than recursed forever.
      def specialize(descriptor, model, seen = {})
        return descriptor if seen[descriptor.__id__]
        seen[descriptor.__id__] = true
        associations = descriptor.associations.map do |association|
          child_model = reflected_child_model(model, association)
          next association if child_model.nil?
          association.with(descriptor: specialize(association.descriptor, child_model, seen))
        end
        descriptor.with(model: model, associations: associations)
      end

      # @param model [Class] the parent Model being specialized against
      # @param association [Panko::CodeGen::Association]
      # @return [Class, nil] the reflected child Model, or +nil+ when the
      #   child must stay on its current path
      def reflected_child_model(model, association)
        return nil unless association.descriptor.model.nil?
        return nil unless model.respond_to?(:reflect_on_association)
        reflection = model.reflect_on_association(association.source)
        return nil if reflection.nil? || reflection.polymorphic?
        klass = begin
          reflection.klass
        rescue NameError
          # +class_name:+ pointing at an undefined constant resolves lazily;
          # an unresolvable edge simply isn't specializable.
          nil
        end
        return nil if klass.nil? || klass.name.nil?
        return nil unless klass.respond_to?(:columns_hash) && klass.respond_to?(:attribute_methods_generated?)
        klass
      end
      private_class_method :reflected_child_model

      # @param decl [Panko::Serializer::AssociationDecl]
      def to_association(decl)
        Association.new(name: decl.name_str.to_sym, kind: decl.kind, descriptor: decl.descriptor, source: decl.name_sym)
      end
      private_class_method :to_association

      def narrow_by(descriptor, engine)
        only_set = engine[:only]&.to_set
        except_set = engine[:except]&.to_set
        descriptor.with(
          attributes: descriptor.attributes.reject { |a| drop?(a.name, only_set, except_set) },
          method_attributes: descriptor.method_attributes.reject { |m| drop?(m.name, only_set, except_set) },
          associations: descriptor.associations.reject { |as| drop?(as.name, only_set, except_set) }.map do |as|
            sub = engine[as.source]
            (sub.is_a?(Hash) && !sub.empty?) ? as.with(descriptor: narrow_by(as.descriptor, sub)) : as
          end
        )
      end
      private_class_method :narrow_by

      def drop?(name, only_set, except_set)
        if only_set
          !only_set.include?(name)
        elsif except_set
          except_set.include?(name)
        else
          false
        end
      end
      private_class_method :drop?

      def blank?(filter)
        filter.nil? || (filter.respond_to?(:empty?) && filter.empty?)
      end
      private_class_method :blank?
    end
  end
end
