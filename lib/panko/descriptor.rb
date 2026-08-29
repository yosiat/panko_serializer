# frozen_string_literal: true

require_relative "code_gen/serializer_cache"

module Panko
  # Public, read-only view of a serializer's shape — the stable introspection
  # surface for tools like association preloaders. Decoupled from the engine's
  # Panko::CodeGen::Descriptor so its internals stay free to change.
  class Descriptor
    Attribute = Data.define(:name, :source)
    MethodAttribute = Data.define(:name, :source)
    Association = Data.define(:name, :source, :kind, :descriptor)

    attr_reader :serializer, :attributes, :method_attributes, :associations

    # The static view is built once per serializer class and cached on the
    # class itself. A concurrent first build races benignly: both threads
    # produce equal frozen views and the last write wins.
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

    # +source+ is the serializer method the field dispatches to — Panko's DSL
    # always produces Symbol bodies; a Callable body (engine-only shape) has
    # no method name, so +source+ is nil there.
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

    # Lazy filtered view — mirrors the engine's runtime Filter design instead
    # of eagerly narrowing a copied tree: it holds the class-level skeleton
    # plus the same engine-shaped filters Hash the serialize path passes to
    # Filter.wrap, and resolves survivors on first read, memoized per level.
    # Only the levels a caller actually visits are ever computed. Memoization
    # races benignly: equal frozen values, last write wins.
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

      # Associations keep/drop and descend by +source+ — the declared
      # relation is the filter key at both the level and the sub-filter,
      # matching the runtime FIELD_INDEX and Panko 0.8.5.
      def associations
        @associations ||= @skeleton.associations.filter_map do |as|
          next unless keep?(as.source)
          sub = @filters[as.source]
          (sub.is_a?(Hash) && !sub.empty?) ? as.with(descriptor: Filtered.new(as.descriptor, sub)) : as
        end.freeze
      end

      private

      # Same drop rule as the engine Filter: :only wins over :except (the two
      # never co-exist at one level in FilterAdapter output).
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
