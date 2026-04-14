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

    # Returns the compiled generated class for this descriptor,
    # cached on the canonical (class-level) descriptor.
    #
    # @return [Class<Panko::CodeGen::GeneratedBase>]
    def engine_serializer
      @engine_serializer ||= begin
        canonical = type._descriptor
        canonical._compiled_class ||= Panko::CodeGen::Compiler.new(canonical).compile
      end
    end

    # The compiled CodeGen class for this descriptor. Only set on
    # the canonical (class-level) descriptor.
    #
    # @return [Class, nil]
    attr_accessor :_compiled_class

    # Returns the FilterMask for this descriptor relative to the canonical
    # (class-level) descriptor. Returns nil when no filtering is needed
    # (unfiltered path).
    #
    # Computed once per descriptor and memoized.
    #
    # @return [Panko::CodeGen::FilterMask, nil]
    def _filter_mask
      return @_filter_mask if defined?(@_filter_mask)

      @_filter_mask = self.class.compute_filter_mask(self, type._descriptor)
    end

    # Computes a FilterMask comparing +filtered+ against +canonical+.
    # Returns nil when all fields match (no filtering needed).
    #
    # @param filtered [SerializationDescriptor] the possibly-filtered descriptor
    # @param canonical [SerializationDescriptor] the canonical (full) descriptor
    # @return [Panko::CodeGen::FilterMask, nil]
    def self.compute_filter_mask(filtered, canonical)
      return nil if filtered.equal?(canonical)

      filtered_attr_names = filtered.attributes.map(&:name).to_set
      attrs_mask = canonical.attributes.map { |a| filtered_attr_names.include?(a.name) }

      filtered_mf_names = filtered.method_fields.map(&:name).to_set
      mf_mask = canonical.method_fields.map { |mf| filtered_mf_names.include?(mf.name) }

      filtered_ho_names = filtered.has_one_associations.map(&:name_sym).to_set
      ho_mask = canonical.has_one_associations.map { |a| filtered_ho_names.include?(a.name_sym) }

      filtered_hm_names = filtered.has_many_associations.map(&:name_sym).to_set
      hm_mask = canonical.has_many_associations.map { |a| filtered_hm_names.include?(a.name_sym) }

      # Recursively build nested masks for included associations
      ho_sub_masks = canonical.has_one_associations.each_with_index.map do |assoc, i|
        next nil unless ho_mask[i]
        filtered_assoc = filtered.has_one_associations.find { |fa| fa.name_sym == assoc.name_sym }
        compute_filter_mask(filtered_assoc.descriptor, assoc.descriptor.type._descriptor)
      end

      hm_sub_masks = canonical.has_many_associations.each_with_index.map do |assoc, i|
        next nil unless hm_mask[i]
        filtered_assoc = filtered.has_many_associations.find { |fa| fa.name_sym == assoc.name_sym }
        compute_filter_mask(filtered_assoc.descriptor, assoc.descriptor.type._descriptor)
      end

      # All included? No mask needed.
      return nil if attrs_mask.all? && mf_mask.all? && ho_mask.all? && hm_mask.all? &&
        ho_sub_masks.all?(&:nil?) && hm_sub_masks.all?(&:nil?)

      Panko::CodeGen::FilterMask.new(
        attrs: attrs_mask,
        method_fields: mf_mask.empty? ? nil : mf_mask,
        has_one: ho_mask.empty? ? nil : ho_mask,
        has_many: hm_mask.empty? ? nil : hm_mask,
        has_one_masks: (ho_sub_masks.any? { |m| !m.nil? }) ? ho_sub_masks : nil,
        has_many_masks: (hm_sub_masks.any? { |m| !m.nil? }) ? hm_sub_masks : nil
      )
    end

    #
    # Applies attributes and association filters
    #
    def apply_filters(options)
      Panko::Filters.apply(self, options)
    end
  end
end
