# frozen_string_literal: true
require_relative "serialization_descriptor"
require "oj"

module Panko
  class Serializer
    class << self
      def inherited(base)
        base._descriptor = Panko::SerializationDescriptor.new
        base._descriptor.type = base

        base._descriptor.attributes = []
        base._descriptor.aliases = {}

        base._descriptor.method_fields = []

        base._descriptor.has_many_associations = []
        base._descriptor.has_one_associations = []
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
        return if @_descriptor.nil?
        @_descriptor.attributes.delete(method)
        @_descriptor.method_fields << method
      end

      def has_one(name, options = {})
        serializer_const = options[:serializer]
        serializer_const = Panko::SerializerResolver.resolve(name.to_s) if serializer_const.nil?

        if serializer_const.nil?
          raise "Can't find serializer for #{self.name}.#{name} has_one relationship."
        end

        @_descriptor.has_one_associations << Panko::Association.new(
          name,
          name.to_s,
          Panko::SerializationDescriptor.build(serializer_const, options)
        )
      end

      def has_many(name, options = {})
        serializer_const = options[:serializer] || options[:each_serializer]
        serializer_const = Panko::SerializerResolver.resolve(name.to_s) if serializer_const.nil?

        if serializer_const.nil?
          raise "Can't find serializer for #{self.name}.#{name} has_many relationship."
        end

        @_descriptor.has_many_associations << Panko::Association.new(
          name,
          name.to_s.freeze,
          Panko::SerializationDescriptor.build(serializer_const, options)
        )
      end
    end

    def initialize(options = {})
      @descriptor = Panko::SerializationDescriptor.build(self.class, options)
      @context = options[:context]
    end

    attr_reader :object, :context

    def serialize(object)
      Oj.load(serialize_to_json(object))
    end

    def serialize_to_json(object)
      writer = Oj::StringWriter.new(mode: :rails)
      Panko::serialize_subject(object, writer, @descriptor, @context)
      writer.to_s
    end

    def reset
      @object = nil
      @context = nil

      self
    end
  end
end
