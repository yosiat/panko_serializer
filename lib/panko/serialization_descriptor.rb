# frozen_string_literal: true
module Panko
  module SerializationDescriptorBuilder
    def self.apply_filters(backend, options)
      serializer_only_filters, attributes_only_filters = resolve_filters(options, :only)
      serializer_except_filters, attributes_except_filters = resolve_filters(options, :except)

      backend.fields = apply_fields_filters(
        backend.fields,
        serializer_only_filters,
        serializer_except_filters
      )

      backend.method_fields = apply_fields_filters(
        backend.method_fields,
        serializer_only_filters,
        serializer_except_filters
      )

      backend.has_many_associations = build_associations(
        apply_association_filters(
          backend.has_many_associations,
          serializer_only_filters,
          serializer_except_filters
        ),
        attributes_only_filters,
        attributes_except_filters
      )

      backend.has_one_associations = build_associations(
        apply_association_filters(
          backend.has_one_associations,
          serializer_only_filters,
          serializer_except_filters
        ),
        attributes_only_filters,
        attributes_except_filters
      )
    end

    def self.duplicate(descriptor)
      backend = Panko::SerializationDescriptor.new

      backend.type = descriptor.type

      backend.fields = descriptor.fields
      backend.method_fields = descriptor.method_fields

      backend.has_many_associations = descriptor.has_many_associations
      backend.has_one_associations = descriptor.has_one_associations

      backend
    end

    def self.build(serializer, options={})
      backend = duplicate(serializer._descriptor)

      apply_filters(backend, options)

      backend
    end

    def self.build_associations(associations, attributes_only_filters, attributes_except_filters)
      associations.each do |association|
        name = association.first
        descriptor = association.last


        options = {
          only: attributes_only_filters.fetch(name, []),
          except: attributes_except_filters.fetch(name, [])
        }

        apply_filters(descriptor, options)
      end
    end

    def self.resolve_filters(options, filter)
      filters = options.fetch(filter, {})
      if filters.is_a? Array
        return filters, {}
      end

      # hash filters looks like this
      # { instance: [:a], foo: [:b] }
      # which mean, for the current instance use `[:a]` as filter
      # and for association named `foo` use `[:b]`

      return [], {} if filters.empty?

      serializer_filters = filters.fetch(:instance, [])
      association_filters = filters.except(:instance)

      return serializer_filters, association_filters
    end

    def self.apply_fields_filters(fields, only, except)
      return fields & only unless only.empty?
      return fields - except unless except.empty?

      fields
    end

    def self.apply_association_filters(associations, only, except)
      unless only.empty?
        return associations.select { |assoc| only.include?(assoc.first) }
      end

      unless except.empty?
        return associations.reject { |assoc| except.include?(assoc.first) }
      end

      associations
    end

    def self.resolve_serializer(serializer)
      Object.const_get(serializer.name)
    end
  end
end
