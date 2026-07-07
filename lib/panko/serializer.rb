# frozen_string_literal: true

require_relative "serialization_descriptor"
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

    class << self
      def inherited(base)
        if _descriptor.nil?
          base._descriptor = Panko::SerializationDescriptor.new

          base._descriptor.attributes = []
          base._descriptor.aliases = {}

          base._descriptor.method_fields = []

          base._descriptor.has_many_associations = []
          base._descriptor.has_one_associations = []
        else
          base._descriptor = Panko::SerializationDescriptor.duplicate(_descriptor)
        end
        base._descriptor.type = base
      end

      attr_accessor :_descriptor

      def attributes(*attrs)
        @_descriptor.attributes.push(*attrs.map { |attr| Attribute.create(attr) }).uniq!
      end

      def aliases(aliases = {})
        aliases.each do |attr, alias_name|
          @_descriptor.attributes << Attribute.create(attr, alias_name: alias_name)
        end
      end

      def method_added(method)
        super

        return if @_descriptor.nil?

        deleted_attr = @_descriptor.attributes.delete(method)
        @_descriptor.method_fields << Attribute.create(deleted_attr.name, alias_name: deleted_attr.alias_name) unless deleted_attr.nil?
      end

      def has_one(name, options = {})
        serializer_const = options[:serializer]
        if serializer_const.is_a?(String)
          serializer_const = Panko::SerializerResolver.resolve(serializer_const, self)
        end
        serializer_const ||= Panko::SerializerResolver.resolve(name.to_s, self)

        raise "Can't find serializer for #{self.name}.#{name} has_one relationship." if serializer_const.nil?

        @_descriptor.has_one_associations << Panko::Association.new(
          name,
          options.fetch(:name, name).to_s,
          Panko::SerializationDescriptor.build(serializer_const, options)
        )
      end

      def has_many(name, options = {})
        serializer_const = options[:serializer] || options[:each_serializer]
        if serializer_const.is_a?(String)
          serializer_const = Panko::SerializerResolver.resolve(serializer_const, self)
        end
        serializer_const ||= Panko::SerializerResolver.resolve(name.to_s, self)

        raise "Can't find serializer for #{self.name}.#{name} has_many relationship." if serializer_const.nil?

        @_descriptor.has_many_associations << Panko::Association.new(
          name,
          options.fetch(:name, name).to_s,
          Panko::SerializationDescriptor.build(serializer_const, options)
        )
      end
    end

    def initialize(options = {})
      # +_skip_init+ builds a bare instance for descriptor duplication
      # (see SerializationDescriptor.duplicate).
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
    attr_writer :serialization_context

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
