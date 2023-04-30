# frozen_string_literal: true

require_relative "serialization_descriptor"
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
    SKIP = Object.new.freeze

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
        super(method)

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
      # this "_skip_init" trick is so I can create serializers from serialization descriptor
      return if options[:_skip_init]

      @serialization_context = SerializationContext.create(options)
      @descriptor = Panko::SerializationDescriptor.build(self.class, options, @serialization_context)
      @used = false
    end

    def context
      @serialization_context.context
    end

    def scope
      @serialization_context.scope
    end

    attr_writer :serialization_context
    attr_reader :object

    def serialize(object)
      serialize_with_writer(object, Panko::ObjectWriter.new).output
    end

    def serialize_to_json(object)
      serialize_with_writer(object, Oj::StringWriter.new(mode: :rails)).to_s
    end

    private

    def serialize_with_writer(object, writer)
      raise ArgumentError.new("Panko::Serializer instances are single-use") if @used
      Panko.serialize_object(object, writer, @descriptor)
      @used = true
      writer
    end
  end
end
