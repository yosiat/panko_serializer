# frozen_string_literal: true

module Panko
  class SerializationDescriptor
    #
    # Creates new description and apply the options
    # on the new descriptor
    #
    def self.build(serializer, options = {}, serialization_context = nil)
      options.merge! serializer.filters_for(options[:context], options[:scope]) if serializer.respond_to? :filters_for
      options.merge! serializer.send(:filters_for_groups, options[:group]) if options[:only].nil? || options[:only].empty?
      
      backend = Panko::SerializationDescriptor.duplicate(serializer._descriptor)

      backend.apply_filters(options)

      backend.set_serialization_context(serialization_context)

      backend
    end

    #
    # Create new descriptor with same properties
    # useful when you want to apply filters
    #
    def self.duplicate(descriptor)
      backend = Panko::SerializationDescriptor.new

      backend.type = descriptor.type

      backend.attributes = descriptor.attributes.dup

      backend.method_fields = descriptor.method_fields.dup
      backend.serializer = descriptor.type.new(_skip_init: true) unless backend.method_fields.empty?

      backend.has_many_associations = descriptor.has_many_associations.map(&:duplicate)
      backend.has_one_associations = descriptor.has_one_associations.map(&:duplicate)

      backend
    end

    def set_serialization_context(context)
      serializer.serialization_context = context if !method_fields.empty? && !serializer.nil?

      has_many_associations.each do |assoc|
        assoc.descriptor.set_serialization_context context
      end

      has_one_associations.each do |assoc|
        assoc.descriptor.set_serialization_context context
      end
    end

    #
    # Applies attributes and association filters
    #
    def apply_filters(options)
      return unless options.key?(:only) || options.key?(:except)

      attributes_only_filters, associations_only_filters = resolve_filters(options, :only)
      attributes_except_filters, associations_except_filters = resolve_filters(options, :except)

      self.attributes = apply_attribute_filters(
        attributes,
        attributes_only_filters,
        attributes_except_filters
      )

      self.method_fields = apply_attribute_filters(
        method_fields,
        attributes_only_filters,
        attributes_except_filters
      )

      unless has_many_associations.empty?
        self.has_many_associations = apply_association_filters(
          has_many_associations,
          { attributes: attributes_only_filters, associations: associations_only_filters },
          attributes: attributes_except_filters, associations: associations_except_filters
        )
      end

      unless has_one_associations.empty?
        self.has_one_associations = apply_association_filters(
          has_one_associations,
          { attributes: attributes_only_filters, associations: associations_only_filters },
          attributes: attributes_except_filters, associations: associations_except_filters
        )
      end
    end

    def apply_association_filters(associations, only_filters, except_filters)
      attributes_only_filters = only_filters[:attributes] || []
      unless attributes_only_filters.empty?
        associations.select! do |association|
          attributes_only_filters.include?(association.name_sym)
        end
      end

      attributes_except_filters = except_filters[:attributes] || []
      unless attributes_except_filters.empty?
        associations.reject! do |association|
          attributes_except_filters.include?(association.name_sym)
        end
      end

      associations_only_filters = only_filters[:associations]
      associations_except_filters = except_filters[:associations]

      return associations if associations_only_filters.empty? && associations_except_filters.empty?

      associations.map do |association|
        name = association.name_sym
        descriptor = association.descriptor

        only_filter = associations_only_filters[name]
        except_filter = associations_except_filters[name]

        filters = {}
        filters[:only] = only_filter unless only_filter.nil?
        filters[:except] = except_filter unless except_filter.nil?

        unless filters.empty?
          next Panko::Association.new(
            name,
            association.name_str,
            Panko::SerializationDescriptor.build(descriptor.type, filters)
          )
        end

        association
      end
    end

    def resolve_filters(options, filter)
      filters = options.fetch(filter, {})
      return filters, {} if filters.is_a? Array

      # hash filters looks like this
      # { instance: [:a], foo: [:b] }
      # which mean, for the current instance use `[:a]` as filter
      # and for association named `foo` use `[:b]`

      return [], {} if filters.empty?

      attributes_filters = filters.fetch(:instance, [])
      association_filters = filters.except(:instance)

      [attributes_filters, association_filters]
    end

    def apply_fields_filters(fields, only, except)
      return fields & only unless only.empty?
      return fields - except unless except.empty?

      fields
    end

    def apply_attribute_filters(attributes, only, except)
      unless only.empty?
        attributes = attributes.select do |attribute|
          name_to_check = attribute.name
          name_to_check = attribute.alias_name unless attribute.alias_name.nil?

          only.include?(name_to_check.to_sym)
        end
      end

      unless except.empty?
        attributes = attributes.reject do |attribute|
          name_to_check = attribute.name
          name_to_check = attribute.alias_name unless attribute.alias_name.nil?

          except.include?(name_to_check.to_sym)
        end
      end

      attributes
    end
  end
end
