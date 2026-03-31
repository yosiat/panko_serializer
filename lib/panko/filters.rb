# frozen_string_literal: true

module Panko
  class Filters
    EMPTY = {}.freeze

    INSTANCE = new.freeze

    # Applies attribute and association filters from +options+ to +descriptor+ in place.
    # Called once per descriptor during build to resolve :only/:except options.
    #
    # @param descriptor [Panko::SerializationDescriptor] the descriptor to mutate
    # @param options [Hash] serializer options (may contain :only, :except)
    # @return [void]
    def self.apply(descriptor, options)
      INSTANCE.apply(descriptor, options)
    end

    def apply(descriptor, options)
      return unless options.key?(:only) || options.key?(:except)

      attributes_only_filters, associations_only_filters = resolve(options, :only)
      attributes_except_filters, associations_except_filters = resolve(options, :except)

      descriptor.attributes = filter_attributes(descriptor.attributes, attributes_only_filters, attributes_except_filters)
      descriptor.method_fields = filter_attributes(descriptor.method_fields, attributes_only_filters, attributes_except_filters)

      unless descriptor.has_many_associations.empty?
        descriptor.has_many_associations = filter_associations(
          descriptor.has_many_associations,
          {attributes: attributes_only_filters, associations: associations_only_filters},
          attributes: attributes_except_filters, associations: associations_except_filters
        )
      end

      unless descriptor.has_one_associations.empty?
        descriptor.has_one_associations = filter_associations(
          descriptor.has_one_associations,
          {attributes: attributes_only_filters, associations: associations_only_filters},
          attributes: attributes_except_filters, associations: associations_except_filters
        )
      end
    end

    private

    # Resolves the :only or :except value from +options+ into a pair of
    # [attribute_filters, association_filters].
    #
    # @param options [Hash] serializer options
    # @param filter [Symbol] :only or :except
    # @return [Array(Array, Hash)] attribute filter array and association filter hash
    def resolve(options, filter)
      filters = options.fetch(filter, EMPTY)
      return filters, EMPTY if filters.is_a?(Array)

      return [], EMPTY if filters.empty?

      attributes_filters = filters.fetch(:instance, [])
      association_filters = filters.except(:instance)

      [attributes_filters, association_filters]
    end

    # Applies +only+ and +except+ filters to an array of attributes,
    # returning the filtered array.
    #
    # @param attributes [Array<Panko::Attribute>] the attributes to filter
    # @param only [Array<Symbol>] allowlist of attribute names
    # @param except [Array<Symbol>] denylist of attribute names
    # @return [Array<Panko::Attribute>]
    def filter_attributes(attributes, only, except)
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

    # Applies inclusion/exclusion filters to an array of associations,
    # returning the filtered (and potentially re-built) array.
    #
    # @param associations [Array<Panko::Association>] the associations to filter
    # @param only_filters [Hash] :attributes and :associations allowlists
    # @param except_filters [Hash] :attributes and :associations denylists
    # @return [Array<Panko::Association>]
    def filter_associations(associations, only_filters, except_filters)
      attributes_only_filters = only_filters[:attributes] || []
      unless attributes_only_filters.empty?
        associations = associations.select do |association|
          attributes_only_filters.include?(association.name_sym)
        end
      end

      attributes_except_filters = except_filters[:attributes] || []
      unless attributes_except_filters.empty?
        associations = associations.reject do |association|
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
  end
end
