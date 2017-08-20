# frozen_string_literal: true
module Panko
  module SerializationDescriptorBuilder
    def self.build(serializer, options={})
      backend = Panko::SerializationDescriptor.new

      serializer_only_filters, attributes_only_filters = resolve_filters(options, :only)
      serializer_except_filters, attributes_except_filters = resolve_filters(options, :except)

      fields, method_fields = fields_of(serializer)

      backend.type = serializer

      backend.fields = apply_fields_filters(
        fields,
        serializer_only_filters,
        serializer_except_filters
      )
      backend.fields = backend.fields.map &:to_s

      backend.method_fields = apply_fields_filters(
        method_fields,
        serializer_only_filters,
        serializer_except_filters
      )

      backend.has_many_associations = build_associations(
        apply_association_filters(
          serializer._has_many_associations,
          serializer_only_filters,
          serializer_except_filters
        ),
        attributes_only_filters,
        attributes_except_filters
      )

      backend.has_one_associations = build_associations(
        apply_association_filters(
          serializer._has_one_associations,
          serializer_only_filters,
          serializer_except_filters
        ),
        attributes_only_filters,
        attributes_except_filters
      )

      backend
    end

    def self.fields_of(serializer)
      fields = []
      method_fields = []

      serializer._attributes.each do |attribute|
        if serializer.method_defined? attribute
          method_fields << attribute
        else
          fields << attribute
        end
      end

      return fields, method_fields
    end

    def self.build_associations(associations, attributes_only_filters, attributes_except_filters)
      associations.map do |association|
        options = association[:options]
        serializer_const = resolve_serializer(options[:serializer])

        options[:only] = options.fetch(:only, []) + attributes_only_filters.fetch(association[:name], [])
        options[:except] = options.fetch(:except, []) + attributes_except_filters.fetch(association[:name], [])

        [
          association[:name],
          SerializationDescriptorBuilder.build(serializer_const, options.except(:serializer))
        ]
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

      serializer_filters = filters.fetch(:instance, [])
      association_filters = filters.except(:instance)

      return serializer_filters, association_filters
    end

    def self.apply_fields_filters(fields, only, except)
      return fields & only if only.present?
      return fields - except if except.present?

      fields
    end

    def self.apply_association_filters(associations, only, except)
      if only.present?
        return associations.select { |assoc| only.include?(assoc[:name]) }
      end

      if except.present?
        return associations.reject { |assoc| except.include?(assoc[:name]) }
      end

      associations
    end

    def self.resolve_serializer(serializer)
      Object.const_get(serializer.name)
    end
  end
end
