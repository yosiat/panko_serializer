# frozen_string_literal: true
module Panko
  class SerializationDescriptor
    #
    # Creates new description and apply the options
    # on the new descriptor
    #
    def self.build(serializer, options={})
      backend = Panko::SerializationDescriptor.duplicate(serializer._descriptor)
      backend.apply_filters(options)
      backend
    end

    #
    # Create new descriptor with same properties
    # useful when you want to apply filters
    #
    def self.duplicate(descriptor)
      backend = Panko::SerializationDescriptor.new

      backend.type = descriptor.type

      backend.fields = descriptor.fields
      backend.method_fields = descriptor.method_fields

      backend.has_many_associations = descriptor.has_many_associations
      backend.has_one_associations = descriptor.has_one_associations

      backend.aliases = descriptor.aliases

      backend
    end

    #
    # Applies attributes and association filters
    #
    def apply_filters(options)
      attributes_only_filters, associations_only_filters = resolve_filters(options, :only)
      attributes_except_filters, associations_except_filters = resolve_filters(options, :except)

      self.fields = apply_fields_filters(
        self.fields,
        attributes_only_filters,
        attributes_except_filters
      )

      self.method_fields = apply_fields_filters(
        self.method_fields,
        attributes_only_filters,
        attributes_except_filters
      )

      self.has_many_associations = apply_association_filters(
        self.has_many_associations,
        { attributes: attributes_only_filters, associations: associations_only_filters },
        { attributes: attributes_except_filters, associations: associations_except_filters }
      )

      self.has_one_associations = apply_association_filters(
        self.has_one_associations,
        { attributes: attributes_only_filters, associations: associations_only_filters },
        { attributes: attributes_except_filters, associations: associations_except_filters }
      )
    end

    def apply_association_filters(associations, only_filters, except_filters)
      attributes_only_filters = only_filters[:attributes]
      attributes_only_filters = associations.map(&:first) if attributes_only_filters.empty?
      attributes_except_filters = except_filters[:attributes] || []


      associations.map do |association|
        name = association.first
        next if attributes_except_filters.include? name
        next unless attributes_only_filters.include? name

        descriptor = association.last

        only_filter = only_filters[:associations][name]
        except_filter = except_filters[:associations][name]

        filters = {}
        filters[:only] = only_filter unless only_filter.nil?
        filters[:except] = except_filter unless except_filter.nil?

        descriptor.apply_filters(filters) unless filters.empty?

        association
      end.compact
    end

    def resolve_filters(options, filter)
      filters = options.fetch(filter, {})
      if filters.is_a? Array
        return filters, {}
      end

      # hash filters looks like this
      # { instance: [:a], foo: [:b] }
      # which mean, for the current instance use `[:a]` as filter
      # and for association named `foo` use `[:b]`

      return [], {} if filters.empty?

      attributes_filters = filters.fetch(:instance, [])
      association_filters = filters.except(:instance)

      return attributes_filters, association_filters
    end

    def apply_fields_filters(fields, only, except)
      return fields & only unless only.empty?
      return fields - except unless except.empty?

      fields
    end
  end
end
