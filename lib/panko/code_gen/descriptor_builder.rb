# frozen_string_literal: true

require_relative "../code_gen"
require_relative "filter_adapter"

module Panko
  module CodeGen
    # Assembles an immutable +Panko::CodeGen::Descriptor+ from a
    # +Panko::Serializer+ class's accumulated DSL declarations (its
    # +_cg_attributes+ / +_cg_method_attributes+ / +_cg_associations+). The DSL
    # already stores Fields as the engine's own +Attribute+ / +MethodAttribute+ /
    # +Association+ value objects and builds each Association's nested
    # Descriptor eagerly when the association is declared (see
    # +Panko::Serializer.has_one+/+has_many+),
    # snapshotting the target serializer as it stands then — matching Panko's
    # finite, one-level self-recursion — so this assembly never recurses.
    module DescriptorBuilder
      module_function

      # @param serializer_class [Class] a Panko::Serializer subclass
      # @return [Panko::CodeGen::Descriptor] the Generic-path base
      #   Descriptor; {specialize} fills +model+ per record class at
      #   auto-specialization compile time
      def build(serializer_class)
        Descriptor.new(
          name: descriptor_name(serializer_class),
          model: nil,
          attributes: serializer_class._cg_attributes.dup,
          method_attributes: serializer_class._cg_method_attributes.dup,
          associations: serializer_class._cg_associations.dup,
          parent_class: serializer_class
        )
      end

      # Anonymous serializers still need a unique, valid generated-class stem.
      # "::" is mangled away: the stem becomes a constant defined inside the
      # anonymous compile namespace, where a qualified name would reopen the
      # real outer module (and const_get rejects qualified Symbols).
      def descriptor_name(serializer_class)
        name = serializer_class.name || "PankoSerializer#{serializer_class.object_id}"
        name.gsub("::", "__")
      end

      # Rebuilds the tree so every Descriptor has a unique +name+. Panko snapshots
      # a self-referential association one level deep (a distinct Descriptor of
      # the same serializer class as its parent), so two Descriptors can share a
      # name — and the engine emits one Generated Class per Descriptor, keyed on
      # +name+, so a shared name reopens the same class and corrupts it. Walks
      # post-order (children first) and suffixes the 2nd+ occurrence of each name.
      def uniquify_names(descriptor, seen = Hash.new(0))
        associations = descriptor.associations.map do |association|
          association.with(
            descriptor: uniquify_names(association.descriptor, seen),
            variants: association.variants.map { |variant| uniquify_names(variant, seen) }
          )
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
      # association's child Model: the auto-specialization tree fill
      # (SerializerCache.variant_pool). The child's Model is the reflected AR
      # class when the source is a reflection on the parent Model, else the
      # one class the child serializer declares with +models+ (a plain method
      # source, such as a filtered copy of an association). A child
      # Descriptor is left untouched when it declared its own Model, or when
      # neither rule yields exactly one AR-like class with a resolvable
      # name; the child then stays on the Generic path, and per-record
      # guards keep the tree safe regardless.
      #
      # Several declared classes become +Association#variants+: one
      # specialized child per class, picked per record by exact class, with
      # the unspecialized child for any other record. Callers run
      # {uniquify_names} on the result, since variants of one child share
      # its name.
      #
      # +seen+ breaks cycles defensively: Panko-built trees are acyclic (a
      # self-referential association snapshots one level deep), but the engine
      # accepts cyclic graphs, and a revisited Descriptor is returned
      # unspecialized rather than recursed forever.
      def specialize(descriptor, model, seen = {})
        return descriptor if seen[[descriptor.__id__, model]]
        seen[[descriptor.__id__, model]] = true
        associations = descriptor.associations.map do |association|
          child_models = child_models(model, association)
          case child_models.size
          when 0 then association
          when 1 then association.with(descriptor: specialize(association.descriptor, child_models.first, seen))
          else
            association.with(variants: child_models.map { |child_model| specialize(association.descriptor, child_model, seen) })
          end
        end
        descriptor.with(model: model, associations: associations)
      end

      # The classes a child is specialized for: the reflected class alone
      # when the source is a reflection, else the specializable classes the
      # child serializer declares with +models+, in declaration order.
      #
      # @param model [Class] the parent Model being specialized against
      # @param association [Panko::CodeGen::Association]
      # @return [Array<Class>] empty when the child must stay on its
      #   current path
      def child_models(model, association)
        return [] unless association.descriptor.model.nil?
        reflection = model.reflect_on_association(association.source) if model.respond_to?(:reflect_on_association)
        return Array(reflected_child_model(reflection)) if reflection
        declared_models(association.descriptor.parent_class).select do |klass|
          specializable?(klass) && serves?(klass, association.descriptor)
        end
      end
      private_class_method :child_models

      # Whether every attribute and association source of +descriptor+ is a
      # column or method on +klass+. A declared model that fails this would
      # stop the whole parent from compiling; it is left out instead, and its
      # records get the unspecialized child.
      def serves?(klass, descriptor)
        ActiveRecord::DefineAttributeMethods.ensure!(klass)
        sources = descriptor.attributes.map(&:source) + descriptor.associations.map(&:source)
        sources.all? do |source|
          ActiveRecord::AccessClassifier.classify(klass, source)
          true
        rescue UnknownSourceError
          false
        end
      end
      private_class_method :serves?

      def declared_models(serializer_class)
        serializer_class.respond_to?(:_cg_models) ? Array(serializer_class._cg_models) : []
      end
      private_class_method :declared_models

      # @param reflection [ActiveRecord::Reflection::AbstractReflection]
      # @return [Class, nil] the reflected child Model, or +nil+ when the
      #   child must stay on its current path
      def reflected_child_model(reflection)
        return nil if reflection.polymorphic?
        klass = begin
          reflection.klass
        rescue
          # +class_name:+ pointing at an undefined constant resolves lazily
          # (NameError), and misdeclared associations can raise other
          # errors (e.g. ArgumentError) — an unresolvable edge simply
          # isn't specializable.
          nil
        end
        specializable?(klass) ? klass : nil
      end
      private_class_method :reflected_child_model

      def specializable?(klass)
        return false if klass.nil? || !resolvable_name?(klass)
        klass.respond_to?(:columns_hash) && klass.respond_to?(:attribute_methods_generated?)
      end
      private_class_method :specializable?

      # The specialized emit guards each body with
      # +record.instance_of?(::<Name>)+, so a Model is only specializable
      # when its name resolves back to the same class object at serialize
      # time — a named-but-unregistered class (+def self.name = "X"+ with
      # no +::X+ constant, or one shadowed by a stub) would bake a guard
      # that raises +NameError+ or silently never matches.
      #
      # @param klass [Class]
      # @return [Boolean]
      def self.resolvable_name?(klass)
        name = klass.name
        return false if name.nil?
        Object.const_defined?(name) && Object.const_get(name).equal?(klass)
      rescue NameError
        false
      end

      def narrow_by(descriptor, engine)
        only_set = engine[:only]&.to_set
        except_set = engine[:except]&.to_set
        descriptor.with(
          attributes: descriptor.attributes.reject { |a| drop?(a.name, only_set, except_set) },
          method_attributes: descriptor.method_attributes.reject { |m| drop?(m.name, only_set, except_set) },
          associations: descriptor.associations.reject { |as| drop?(as.source, only_set, except_set) }.map do |as|
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
