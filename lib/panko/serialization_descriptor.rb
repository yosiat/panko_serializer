# frozen_string_literal: true

module Panko
  class SerializationDescriptor
    attr_accessor :attributes,
      :method_fields,
      :has_one_associations,
      :has_many_associations,
      :type,
      :serializer,
      :attributes_writer

    def initialize
      @attributes = []
      @method_fields = []
      @has_one_associations = []
      @has_many_associations = []
      @type = nil
      @serializer = nil
      @attributes_writer = nil
    end

    #
    # Creates new description and apply the options
    # on the new descriptor
    #
    def self.build(serializer, options = {}, serialization_context = nil)
      backend = Panko::SerializationDescriptor.duplicate(serializer._descriptor)

      options.merge! serializer.filters_for(options[:context], options[:scope]) if serializer.respond_to? :filters_for

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
      Panko::Filters.apply(self, options)
    end
  end
end
