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

      def inherited(base)
        base._cg_attributes = (_cg_attributes || []).dup
        base._cg_method_attributes = (_cg_method_attributes || []).dup
        base._cg_associations = (_cg_associations || []).dup
        base._cg_models = _cg_models
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

    def initialize(options = {})
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

    def serialize(object)
      Panko::CodeGen::Runtime.serialize_one(
        self.class, object, output: :hash, context: @context, scope: @scope, only: @only, except: @except
      )
    end

    def serialize_to_json(object)
      Panko::CodeGen::Runtime.serialize_one(
        self.class, object, output: :json, context: @context, scope: @scope, only: @only, except: @except
      )
    end
  end
end
