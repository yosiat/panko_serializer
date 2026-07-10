# frozen_string_literal: true

require_relative "code_gen"
require_relative "code_gen/descriptor_builder"
require_relative "code_gen/runtime"
require "oj"

class SerializationContext
  attr_accessor :context, :scope

  def initialize(context, scope)
    @context = context
    @scope = scope
  end

  def self.create(options)
    if options.key?(:context) || options.key?(:scope)
      SerializationContext.new(options[:context], options[:scope])
    else
      EmptySerializerContext.new
    end
  end
end

class EmptySerializerContext
  def scope
    nil
  end

  def context
    nil
  end
end

module Panko
  class Serializer
    # Unified with the engine's sentinel so a method field returning SKIP is
    # recognized by the generated code's `value.equal?(Panko::CodeGen::SKIP)` check.
    SKIP = Panko::CodeGen::SKIP

    # A has_one / has_many declaration captured at class-definition time. Its
    # +descriptor+ is the nested Panko::CodeGen::Descriptor, built (and any
    # static only/except narrowed) eagerly when the association is declared.
    AssociationDecl = Struct.new(:name_sym, :name_str, :kind, :descriptor)

    class << self
      # Each serializer accumulates its Fields as the engine's own value
      # objects; SerializerCache freezes them into a Panko::CodeGen::Descriptor
      # on first use. A subclass inherits a copy so its DSL edits stay local.
      attr_accessor :_cg_attributes, :_cg_method_attributes, :_cg_associations, :_cg_models

      # Per-class compile cache: the converted Descriptor, the compiled
      # Generated Class per output mode, and the per-mode InstancePool.
      # Direct class-ivar slots (read on every serialize) so SerializerCache
      # never reaches in reflectively. Not copied on inheritance — each class
      # compiles its own; a Zeitwerk reload mints a fresh class object with
      # empty slots, so the cache self-heals.
      attr_accessor :_cg_descriptor, :_cg_compiled_json, :_cg_compiled_hash,
        :_cg_pool_json, :_cg_pool_hash

      # Whether this class defines +filters_for+, so the unfiltered hot path
      # skips filter resolution entirely. Seeded at inheritance (covers a
      # parent-defined +filters_for+) and flipped by {singleton_method_added}
      # when one is defined later — including an RSpec stub added after the
      # class has already serialized. Never flips back to false; a stale
      # +true+ just re-checks +respond_to?+ inside +runtime_filters+.
      attr_accessor :_cg_has_filters_for

      def inherited(base)
        base._cg_attributes = (_cg_attributes || []).dup
        base._cg_method_attributes = (_cg_method_attributes || []).dup
        base._cg_associations = (_cg_associations || []).dup
        base._cg_models = _cg_models
        base._cg_has_filters_for = base.respond_to?(:filters_for)
      end

      # Mirrors {method_added}: a +filters_for+ defined (or stubbed) after
      # the first serialize must still be honored, since the hot path reads
      # +_cg_has_filters_for+ instead of paying +respond_to?+ per call.
      def singleton_method_added(method)
        super
        @_cg_has_filters_for = true if method == :filters_for
      end

      # Opts this serializer into the engine's Specialized record-access path:
      # attributes read through +record._read_attribute+ (the ActiveRecord fast
      # path) instead of the Generic +record.send+. The caller guarantees every
      # serialized record is an instance of one of +klasses+; each attribute's
      # source must be a column or instance method on every AR class listed, or
      # compilation raises. Calling with no classes keeps the Generic path.
      def models(*klasses)
        flat = klasses.flatten
        @_cg_models = flat.empty? ? nil : flat.freeze
      end

      def attributes(*attrs)
        attrs.each { |attr| add_attribute(attr.to_sym, attr.to_sym) }
      end

      def aliases(aliases = {})
        aliases.each { |source, output| add_attribute(source.to_sym, output.to_sym) }
      end

      # A user-defined method whose name matches a declared attribute turns that
      # attribute into a Symbol-body method field (dispatched on the generated
      # subclass of this serializer), preserving its output key.
      def method_added(method)
        super
        return if _cg_attributes.nil?
        index = _cg_attributes.index { |attribute| attribute.source == method }
        return if index.nil?
        attribute = _cg_attributes.delete_at(index)
        _cg_method_attributes << Panko::CodeGen::MethodAttribute.new(name: attribute.name, body: method)
      end

      def has_one(name, options = {})
        add_association(:has_one, name, options)
      end

      def has_many(name, options = {})
        add_association(:has_many, name, options)
      end

      private

      # De-duplicates by Source (the read method), keeping the first declaration
      # — matching Panko's +attributes(...).uniq!+.
      def add_attribute(source, output)
        return if _cg_attributes.any? { |attribute| attribute.source == source }
        _cg_attributes << Panko::CodeGen::Attribute.new(name: output, source: source)
      end

      def add_association(kind, name, options)
        serializer = resolve_association_serializer(name, options, kind)
        descriptor = Panko::CodeGen::DescriptorBuilder.build(serializer)
        descriptor = Panko::CodeGen::DescriptorBuilder.narrow(descriptor, options[:only], options[:except])
        _cg_associations << AssociationDecl.new(name.to_sym, options.fetch(:name, name).to_s, kind, descriptor)
      end

      def resolve_association_serializer(name, options, kind)
        serializer = options[:serializer] || options[:each_serializer]
        serializer = Panko::SerializerResolver.resolve(serializer, self) if serializer.is_a?(String)
        serializer ||= Panko::SerializerResolver.resolve(name.to_s, self)
        raise "Can't find serializer for #{self.name}.#{name} #{kind} relationship." if serializer.nil?
        serializer
      end
    end

    # Frozen shared default for the no-options construction path — a literal
    # +{}+ default allocates a fresh Hash on every +.new+, which is measurable
    # on single-record serialization.
    EMPTY_OPTIONS = {}.freeze

    def initialize(options = EMPTY_OPTIONS)
      # No-options construction (the common hot path) leaves the ivars
      # uninitialized — Ruby reads them back as nil, same as unpacking an
      # empty Hash, without paying four lookups and four writes per +.new+.
      return if options.equal?(EMPTY_OPTIONS)

      # +_skip_init+ builds a bare instance for descriptor duplication.
      return if options[:_skip_init]

      @context = options[:context]
      @scope = options[:scope]
      @only = options[:only]
      @except = options[:except]
    end

    # The generated +_write_one+ (parent_class dispatch) sets @object /
    # @context / @scope on itself per record, so a user method field reads
    # them off the generated instance it runs on.
    attr_reader :object, :context, :scope

    # Both serialize methods inline the whole seam instead of calling into a
    # shared Runtime entry point: the mode is known statically here, so the
    # pool comes off the class's own slot with no dispatch-layer hop, filter
    # resolution is skipped outright on the unfiltered path, and the
    # checkout/checkin cycle costs one Thread.current lookup. This matters
    # because these shared entry points go polymorphic the moment an app has
    # more than one serializer class.

    def serialize(object)
      klass = self.class
      pool = klass._cg_pool_hash || Panko::CodeGen::SerializerCache.instance_pool(klass, :hash)
      filters = if @only || @except || klass._cg_has_filters_for
        Panko::CodeGen::Runtime.runtime_filters(klass, @context, @scope, @only, @except)
      end
      stack = pool.stack
      instance = stack.pop || pool.build
      begin
        instance.serialize_one(object, context: @context, scope: @scope, filters: filters)
      ensure
        # _release drops the instance tree's per-record @object/@context/@scope
        # before it goes back on the stack — a pooled instance must not pin
        # the last record graph (or request-scoped context) between calls.
        instance._release
        stack.push(instance)
      end
    end

    def serialize_to_json(object)
      klass = self.class
      pool = klass._cg_pool_json || Panko::CodeGen::SerializerCache.instance_pool(klass, :json)
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
