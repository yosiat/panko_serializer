# frozen_string_literal: true

require_relative "code_gen/serializer_cache"

module Panko
  # Public, read-only view of a serializer's shape, for tools like association
  # preloaders. Separate from Panko::CodeGen::Descriptor so the engine can change.
  class Descriptor
    Attribute = Data.define(:name, :source)
    MethodAttribute = Data.define(:name, :source)
    Association = Data.define(:name, :source, :kind, :descriptor)

    attr_reader :serializer, :attributes, :method_attributes, :associations

    # Cached on the serializer class. A concurrent first build is harmless:
    # both threads build frozen views with the same content.
    def self.for(serializer_class)
      serializer_class._cg_public_descriptor ||= wrap(
        CodeGen::SerializerCache.descriptor_for(serializer_class)
      )
    end

    def self.wrap(internal)
      new(
        serializer: internal.parent_class,
        attributes: internal.attributes.map { |a| Attribute.new(name: a.name, source: a.source) }.freeze,
        method_attributes: internal.method_attributes.map { |m| wrap_method_attribute(m) }.freeze,
        associations: internal.associations.map do |as|
          Association.new(name: as.name, source: as.source, kind: as.kind, descriptor: wrap(as.descriptor))
        end.freeze
      ).freeze
    end
    private_class_method :wrap

    # A Callable body has no method name, so +source+ is nil. The DSL only
    # makes Symbol bodies.
    def self.wrap_method_attribute(method_attribute)
      body = method_attribute.body
      MethodAttribute.new(name: method_attribute.name, source: body.is_a?(Symbol) ? body : nil)
    end
    private_class_method :wrap_method_attribute

    def initialize(serializer:, attributes:, method_attributes:, associations:)
      @serializer = serializer
      @attributes = attributes
      @method_attributes = method_attributes
      @associations = associations
    end

    # Resolves each level on first read and memoizes it, so only the levels a
    # caller visits cost anything. +filters+ has the shape
    # Panko::CodeGen::Runtime.runtime_filters returns.
    class Filtered < Descriptor
      def initialize(skeleton, filters)
        @skeleton = skeleton
        @filters = filters
      end

      def serializer
        @skeleton.serializer
      end

      def attributes
        @attributes ||= @skeleton.attributes.select { |a| keep?(a.name) }.freeze
      end

      def method_attributes
        @method_attributes ||= @skeleton.method_attributes.select { |m| keep?(m.name) }.freeze
      end

      # Associations are filtered by +source+, the declared relation name, as
      # the serialize path does.
      def associations
        @associations ||= @skeleton.associations.filter_map do |as|
          next unless keep?(as.source)
          sub = @filters[as.source]
          (sub.is_a?(Hash) && !sub.empty?) ? as.with(descriptor: Filtered.new(as.descriptor, sub)) : as
        end.freeze
      end

      private

      # FilterAdapter never emits both :only and :except at one level.
      def keep?(name)
        only = @filters[:only]
        return only.include?(name) unless only.nil?
        except = @filters[:except]
        return !except.include?(name) unless except.nil?
        true
      end
    end
  end
end
