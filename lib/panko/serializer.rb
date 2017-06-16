require_relative 'attributes/has_one'
require_relative 'attributes/has_many'
require_relative 'attributes/field'
require 'oj'

module Panko
  class Serializer
    class << self
      def inherited(base)
        base._attributes = (_attributes || []).dup
        base._associations = (_associations || []).dup

        @_attributes = []
        @_associations = []
      end

      attr_accessor :_attributes, :_associations

      def attributes *attrs
        @_attributes.concat attrs.map { |attr| FieldAttribute.new(attr) }
      end


      def has_one name, options
        @_associations << HasOneAttribute.new(name, options)
      end

      def has_many name, options
        @_associations << HasManyAttribute.new(name, options)
      end
    end

    def initialize(options = {})
      @context = options.fetch(:context, nil)

      processed_filter = process_filter options.fetch(:only, [])
      @only = processed_filter[:serializer]
      @only_associations = processed_filter[:associations]

      processed_filter = process_filter options.fetch(:except, [])
      @except = processed_filter[:serializer]
      @except_associations = processed_filter[:associations]

      build_attributes_reader
    end

    attr_reader :object, :context

    def serialize(object, writer = nil)
      writer ||= Oj::StringWriter.new(indent: 0, mode: :rails)
      serialize_to_writer object, writer

      Oj.load(writer.to_s)
    end

    private

    def process_filter(filter)
      return { serializer: filter, associations: {} } if filter.is_a? Array

      if filter.is_a? Hash
        # hash filters looks like this
        # { instance: [:a], foo: [:b] }
        # which mean, for the current instance use `[:a]` as filter
        # and for association named `foo` use `[:b]`

        return {
          serializer: filter.fetch(:instance, []),
          associations: filter.except(:instance)
        }
      end
    end

    def build_attributes_reader
      attributes_reader_method_body = <<-EOMETHOD
        def serialize_to_writer object, writer
          @object = object

          writer.push_object

          #{attributes_code}
          #{associations_code}

          writer.pop
        end
      EOMETHOD

      # TODO: don't redefine if [attributes+associations] wasn't changed
      instance_eval attributes_reader_method_body, __FILE__, __LINE__
    end

    #
    # Creates const for the given attr with it's name
    # frozen as value.
    #
    # This is for saving object allocations, so, instead of -
    # `obj["name"] = object.name`
    #
    # we do:
    # ```
    #   # once
    #   NAME = 'name'.freeze
    #
    #   # later
    #   obj[NAME] = object.name
    # ```
    def constantize_attribute(attr)
      const_name = attr.upcase
      unless self.class.const_defined? const_name
        self.class.const_set const_name, attr.to_s.freeze
      end

      const_name
    end

    #
    # Generates the code for serializing attributes
    # The end result of this code for each attributes is pretty simple,
    #
    # For example:
    #   `serializable_object[NAME] = object.name`
    #
    #
    def attributes_code
      filter(self.class._attributes).map do |attr|
        const_name = constantize_attribute attr.name

        #
        # Detects what the reader should be
        #
        # for methods we it's just
        #   `attr`
        # otherwise it is:
        #   `object.attr`
        #
        reader = "object.#{attr.name}"
        if self.class.method_defined? attr.name
          reader = attr.name
        end

        "writer.push_value(#{reader}, #{const_name})"
      end.join("\n")
    end

    def associations_code
      filter(self.class._associations).map do |association|
        const_name = constantize_attribute association.name

        #
        # Create instance variable to store the serializer for reusing of serializer.
        #
        # Example:
        #   For `has_one :foo, serializer: FooSerializer`
        #   @foo_serializer = FooSerializer.new
        #
        serializer_instance_variable = "@#{association.name}_serializer"
        options = {
          context: @context,
          only: @only_associations.fetch(association.name.to_sym, []),
          except: @except_associations.fetch(association.name.to_sym, []),
        }
        serializer = association.create_serializer Object.const_get(association.serializer.name), options

        instance_variable_set serializer_instance_variable, serializer

        # TODO: has_one ? has_many ..

        output = "writer.push_key(#{const_name}) \n"
        output << "#{serializer_instance_variable}.serialize_to_writer(object.#{association.name}, writer)"

        output
      end.join("\n")
    end

    def filter keys
      if not @only.empty?
        return keys.select { |key| @only.include? key.name }
      end

      if not @except.empty?
        return keys.reject { |key| @except.include? key.name }
      end

      keys
    end
  end
end
