# frozen_string_literal: true

require_relative "code_gen"
require_relative "code_gen/descriptor_builder"
require_relative "code_gen/runtime"
require "oj"

module Panko
  class Serializer
    # A method field that returns SKIP leaves its key out of the output.
    SKIP = Panko::CodeGen::SKIP

    EMPTY_MODELS = [].freeze

    class << self
      attr_accessor :_cg_attributes, :_cg_method_attributes, :_cg_associations

      # Not copied on inheritance: each class compiles its own.
      attr_accessor :_cg_state

      # One-entry inline caches: frozen [model, pool] pairs.
      attr_accessor :_cg_last_json, :_cg_last_hash

      attr_accessor :_cg_public_descriptor

      # Lets the unfiltered hot path skip filter resolution. A stale +true+ only
      # costs a +respond_to?+ inside +runtime_filters+.
      attr_accessor :_cg_has_filters_for

      attr_accessor :_cg_models

      def inherited(base)
        base._cg_attributes = (_cg_attributes || []).dup
        base._cg_method_attributes = (_cg_method_attributes || []).dup
        base._cg_associations = (_cg_associations || []).dup
        base._cg_has_filters_for = base.respond_to?(:filters_for)
        base._cg_models = _cg_models || EMPTY_MODELS
      end

      # Declares the record classes this serializer expects, so Panko.compile_all
      # can compile a specialized variant for each at boot. A hint only: records
      # of other classes still serialize. Subclasses inherit the list; a second
      # call replaces it.
      #
      # @param models [Array<Class>]
      # @raise [ArgumentError] when an argument is not a Class
      def models(*models)
        invalid = models.reject { |model| model.is_a?(Class) }
        raise ArgumentError, "models: expected classes, got #{invalid.inspect}" unless invalid.empty?
        self._cg_models = models.freeze
      end

      # A +filters_for+ defined or stubbed after the first serialize must still apply.
      def singleton_method_added(method)
        super
        @_cg_has_filters_for = true if method == :filters_for
      end

      def attributes(*attrs)
        attrs.each { |attr| add_attribute(attr.to_sym, attr.to_sym) }
      end

      def aliases(aliases = {})
        aliases.each { |source, output| add_attribute(source.to_sym, output.to_sym) }
      end

      # A method named like a declared attribute turns that attribute into a
      # method field with the same output key.
      def method_added(method)
        super
        return if _cg_attributes.nil?
        index = _cg_attributes.index { |attribute| attribute.source == method }
        return if index.nil?
        attribute = _cg_attributes.delete_at(index)
        _cg_method_attributes << Panko::CodeGen::MethodAttribute.new(name: attribute.name, body: method)
      end

      # The static public view of this serializer's declared shape.
      def descriptor
        Panko::Descriptor.for(self)
      end

      def has_one(name, options = {})
        add_association(:has_one, name, options)
      end

      def has_many(name, options = {})
        add_association(:has_many, name, options)
      end

      private

      def add_attribute(source, output)
        return if _cg_attributes.any? { |attribute| attribute.source == source }
        _cg_attributes << Panko::CodeGen::Attribute.new(name: output, source: source)
      end

      def add_association(kind, name, options)
        serializer = resolve_association_serializer(name, options, kind)
        descriptor = Panko::CodeGen::DescriptorBuilder.build(serializer)
        only, except = association_filters(serializer, options)
        descriptor = Panko::CodeGen::DescriptorBuilder.narrow(descriptor, only, except)
        _cg_associations << Panko::CodeGen::Association.new(
          name: options.fetch(:name, name).to_s.to_sym,
          kind: kind,
          descriptor: descriptor,
          source: name.to_sym
        )
      end

      # The nested serializer's +filters_for+ runs once, at declaration, with nil
      # context and scope. Its keys win over the declared +only:+/+except:+.
      def association_filters(serializer, options)
        only = options[:only]
        except = options[:except]

        if serializer.respond_to?(:filters_for)
          filters = serializer.filters_for(nil, nil)
          only = filters[:only] if filters.key?(:only)
          except = filters[:except] if filters.key?(:except)
        end

        [only, except]
      end

      def resolve_association_serializer(name, options, kind)
        serializer = options[:serializer] || options[:each_serializer]
        serializer = Panko::SerializerResolver.resolve(serializer, self) if serializer.is_a?(String)
        serializer ||= Panko::SerializerResolver.resolve(name.to_s, self)
        raise "Can't find serializer for #{self.name}.#{name} #{kind} relationship." if serializer.nil?
        serializer
      end
    end

    # A literal +{}+ default would allocate a Hash on every +.new+.
    EMPTY_OPTIONS = {}.freeze

    def initialize(options = EMPTY_OPTIONS)
      # Unset ivars read as nil, so +.new+ skips four Hash lookups and four writes.
      return if options.equal?(EMPTY_OPTIONS)

      @context = options[:context]
      @scope = options[:scope]
      @only = options[:only]
      @except = options[:except]
    end

    # Generated code sets these per record on the instance a method field runs on.
    attr_reader :object, :context, :scope

    # The class-level view, narrowed by this instance's +only+/+except+ and +filters_for+.
    def descriptor
      klass = self.class
      filters = if @only || @except || klass._cg_has_filters_for
        Panko::CodeGen::Runtime.runtime_filters(klass, @context, @scope, @only, @except)
      end
      base = Panko::Descriptor.for(klass)
      filters ? Panko::Descriptor::Filtered.new(base, filters) : base
    end

    # Both methods inline the pool checkout instead of calling a shared Runtime
    # method, which would go polymorphic once an app has more than one serializer.

    def serialize(object)
      klass = self.class
      cached = klass._cg_last_hash
      pool = if cached && object.instance_of?(cached[0])
        cached[1]
      else
        Panko::CodeGen::SerializerCache.variant_pool(klass, :hash, object.class)
      end
      filters = if @only || @except || klass._cg_has_filters_for
        Panko::CodeGen::Runtime.runtime_filters(klass, @context, @scope, @only, @except)
      end
      stack = pool.stack
      instance = stack.pop || pool.build
      begin
        instance.serialize_one(object, context: @context, scope: @scope, filters: filters)
      ensure
        # A pooled instance must not hold the last record or request context.
        instance._release
        stack.push(instance)
      end
    end

    def serialize_to_json(object)
      klass = self.class
      cached = klass._cg_last_json
      pool = if cached && object.instance_of?(cached[0])
        cached[1]
      else
        Panko::CodeGen::SerializerCache.variant_pool(klass, :json, object.class)
      end
      filters = if @only || @except || klass._cg_has_filters_for
        Panko::CodeGen::Runtime.runtime_filters(klass, @context, @scope, @only, @except)
      end
      stack = pool.stack
      instance = stack.pop || pool.build
      begin
        instance.serialize_one(object, context: @context, scope: @scope, filters: filters)
      ensure
        instance._release
        stack.push(instance)
      end
    end
  end
end
