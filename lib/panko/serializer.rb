# frozen_string_literal: true

require_relative "serialization_descriptor"
require "oj"

class SerializationContext
  attr_accessor :context, :scope, :group

  def initialize(context, scope, group)
    @context = context
    @scope = scope
    @group = group
  end

  def self.create(options)
    if options.key?(:context) || options.key?(:scope) || options.key?(:group)
      SerializationContext.new(options[:context], options[:scope], options[:group])
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

  def group
    nil
  end
end

module Panko
  class Serializer
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
        base._default_attributes += _default_attributes
      end

      attr_accessor :_descriptor
      attr_accessor :_default_attributes
      attr_accessor :_groups

      def _default_attributes
        @_default_attributes ||= []
      end

      def attributes(*attrs)
        self._default_attributes += attrs
        _attributes(*attrs)
      end

      def aliases(aliases = {})
        aliases.each do |attr, alias_name|
          self._default_attributes << alias_name
        end
        _aliases(aliases)
      end

      def method_added(method)
        return if @_descriptor.nil?
        deleted_attr = @_descriptor.attributes.delete(method)
        @_descriptor.method_fields << Attribute.create(method) unless deleted_attr.nil?
      end

      def has_one(name, options = {})
        self._default_attributes << name
        _has_one(name, options)
      end

      def has_many(name, options = {})
        self._default_attributes << name
        _has_many(name, options)
      end

      def group(*groups_names, &block)
        new_methods = Proc.new do
          def group_has_one(name, options = {})
            add_groups_field(@group_name, name)
            _has_one(name, options)
          end

          def group_has_many(name, options = {})
            add_groups_field(@group_name, name)
            _has_many(name, options)
          end

          def group_attributes(*attrs)
            attrs.each { |attr| add_groups_field(@group_name, attr) }
            _attributes(*attrs)
          end
        end
        
        combine_block = Proc.new { block.call(new_methods.call) }
        
        init_groups(groups_names, combine_block)
      end

      private

      def filters_for_groups(group)
        return {only: _default_attributes} if !@_groups&.method(:[])&.call(group) or !group
        @group_name = group
        @_groups[group].block.call
        @_groups[group].make_filter()
      end

      def init_groups(groups_names, block)
        groups_names.each do |group_name|
          add_groups_block(group_name, block)
        end
      end

      def add_groups_field(group_name, value)
        if value
          @_groups[group_name.to_sym].fields << value
        end
      end

      def add_groups_block(group_name, block)
        if block
          @_groups                    ||= {}
          @_groups[group_name.to_sym] ||= Group.new(serializer: self)
          @_groups[group_name.to_sym].block  = block
        end
      end

      def _aliases(aliases = {})
        aliases.each do |attr, alias_name|
          @_descriptor.attributes << Attribute.create(attr, alias_name: alias_name)
        end
      end

      def _attributes(*attrs)
        @_descriptor.attributes.push(*attrs.map { |attr| Attribute.create(attr) }).uniq!
      end

      def _has_one(name, options = {})
        serializer_const = options[:serializer]
        serializer_const = Panko::SerializerResolver.resolve(name.to_s) if serializer_const.nil?

        raise "Can't find serializer for #{self.name}.#{name} has_one relationship." if serializer_const.nil?

        @_descriptor.has_one_associations << Panko::Association.new(
          name,
          options.fetch(:name, name).to_s,
          Panko::SerializationDescriptor.build(serializer_const, options)
        )
      end

      def _has_many(name, options = {})
        serializer_const = options[:serializer] || options[:each_serializer]
        serializer_const = Panko::SerializerResolver.resolve(name.to_s) if serializer_const.nil?

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
    end

    def context
      @serialization_context.context
    end

    def scope
      @serialization_context.scope
    end

    def group
      @serialization_context.group
    end

    attr_writer :serialization_context
    attr_reader :object

    def serialize(object)
      Oj.load(serialize_to_json(object))
    end

    def serialize_to_json(object)
      writer = Oj::StringWriter.new(mode: :rails)
      Panko.serialize_object(object, writer, @descriptor)
      @descriptor.set_serialization_context(nil) unless @serialization_context.is_a?(EmptySerializerContext)
      writer.to_s
    end
  end
end
