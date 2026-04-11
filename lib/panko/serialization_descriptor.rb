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
      has_filters = options.key?(:only) || options.key?(:except)
      has_context = options.key?(:context) || options.key?(:scope)

      if serializer.respond_to?(:filters_for)
        extra = serializer.filters_for(options[:context], options[:scope])
        has_filters ||= extra.key?(:only) || extra.key?(:except)
        options.merge!(extra)
      end

      if has_filters || has_context
        backend = Panko::SerializationDescriptor.duplicate(serializer._descriptor)
        backend.apply_filters(options)
        backend.set_serialization_context(serialization_context)
        backend
      else
        # Fast path: no filters, no context — reuse a thread-local copy.
        # Each thread gets its own duplicated descriptor (with its own
        # serializer instance and association caches), avoiding the cost
        # of duplicating on every call while remaining thread-safe.
        descriptor = serializer._thread_local_descriptor
        descriptor.set_serialization_context(serialization_context)
        descriptor
      end
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

    # Returns a cached Engine::Serializer for this descriptor.
    # Safe to reuse on the same thread — Engine::Serializer's mutable state
    # (attributes_writer) handles class changes internally.
    #
    # @return [Panko::Engine::Serializer]
    def engine_serializer
      @engine_serializer ||= Panko::Engine::Serializer.new(self)
    end

    #
    # Applies attributes and association filters
    #
    def apply_filters(options)
      Panko::Filters.apply(self, options)
    end
  end
end
