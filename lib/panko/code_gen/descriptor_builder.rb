# frozen_string_literal: true

require_relative "../code_gen"
require_relative "filter_adapter"

module Panko
  module CodeGen
    # Builds a serializer class's Descriptor from its DSL declarations. Nested Descriptors are
    # built when the association is declared, so +build+ never recurses.
    module DescriptorBuilder
      module_function

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

      # "::" is replaced because the name becomes a constant inside an anonymous namespace, where
      # a qualified name would reopen the real outer module.
      def descriptor_name(serializer_class)
        name = serializer_class.name || "PankoSerializer#{serializer_class.object_id}"
        name.gsub("::", "__")
      end

      # The engine defines one Generated Class per Descriptor object, named after +name+.
      # Equal Descriptors become one object, so two associations using one child serializer share
      # a class and the child's method fields stay monomorphic on +self+. Different Descriptors
      # with one name (a self-reference snapshot, a static filter, another Model) get a suffix.
      # +shared+ is keyed before the final name is set, so equal subtrees give equal keys.
      def uniquify_names(descriptor, seen = Hash.new(0), shared = {})
        associations = descriptor.associations.map do |association|
          association.with(
            descriptor: uniquify_names(association.descriptor, seen, shared),
            variants: association.variants.map { |variant| uniquify_names(variant, seen, shared) }
          )
        end
        rebuilt = descriptor.with(associations: associations)
        shared[rebuilt] ||= begin
          seen[descriptor.name] += 1
          count = seen[descriptor.name]
          rebuilt.with(name: (count == 1) ? descriptor.name : "#{descriptor.name}_#{count}")
        end
      end

      # Bakes a static association filter (+has_many :x, only: [...]+) into the cached Descriptor.
      def narrow(descriptor, only, except)
        return descriptor if blank?(only) && blank?(except)
        narrow_by(descriptor, FilterAdapter.to_engine_filters(only, except))
      end

      # A child with no specializable class is left unchanged. Several declared classes
      # become +Association#variants+, which share a name, so callers run {uniquify_names}.
      # +seen+ keeps each (Descriptor, Model) result, so a child shared by several associations
      # stays one object. A pair still in progress is a cycle and comes back unspecialized.
      def specialize(descriptor, model, seen = {})
        key = [descriptor.__id__, model]
        return seen[key] || descriptor if seen.key?(key)
        seen[key] = nil
        associations = descriptor.associations.map do |association|
          child_models = child_models(model, association)
          case child_models.size
          when 0 then association
          when 1 then association.with(descriptor: specialize(association.descriptor, child_models.first, seen))
          else
            association.with(variants: child_models.map { |child_model| specialize(association.descriptor, child_model, seen) })
          end
        end
        seen[key] = descriptor.with(model: model, associations: associations)
      end

      def child_models(model, association)
        return [] unless association.descriptor.model.nil?
        reflection = model.reflect_on_association(association.source) if model.respond_to?(:reflect_on_association)
        return Array(reflected_child_model(reflection)) if reflection
        declared_models(association.descriptor.parent_class).select do |klass|
          specializable?(klass) && serves?(klass, association.descriptor)
        end
      end
      private_class_method :child_models

      # A declared model missing one of the sources would stop the whole parent from compiling,
      # so it is left out and its records get the unspecialized child.
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

      def reflected_child_model(reflection)
        return nil if reflection.polymorphic?
        klass = begin
          reflection.klass
        rescue
          # An undefined +class_name:+ or a badly declared association raises here; such a child
          # is just not specializable.
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

      # The specialized code checks +record.instance_of?(::<Name>)+, so the name must resolve
      # to this same class object, or the check raises +NameError+ or never matches.
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
