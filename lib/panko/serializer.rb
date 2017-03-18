require_relative 'attributes/has_one'
require_relative 'attributes/has_many'

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
        @_attributes.concat attrs
      end


      def has_one name, options
        serializer = options[:serializer]
        @_associations << HasOneAttribute.new(name, serializer)
      end

      def has_many name, options
        serializer = options[:serializer]
        @_associations << HasManyAttribute.new(name, serializer)
      end
    end

    def initialize options={}
      @only = options.fetch(:only, [])
      @except = options.fetch(:except, [])
      build_attributes_reader
    end

    attr_reader :object

    def serialize object
      serializable_object object, {}
    end

    private

    RETURN_OBJECT = "serialized_object"

    def build_attributes_reader
      attributes_reader_method_body = <<-EOMETHOD
        def serializable_object object, #{RETURN_OBJECT}
          @object = object

          #{attributes_code}
          #{associations_code}

          #{RETURN_OBJECT}
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
    def constantize_attribute attr
      unless self.class.const_defined? attr.upcase
        self.class.const_set attr.upcase, attr.to_s.freeze
      end

      attr.upcase
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
        const_name = constantize_attribute attr

        #
        # Detects what the reader should be
        #
        # for methods we it's just
        #   `attr`
        # otherwise it is:
        #   `object.attr`
        #
        reader = "object.#{attr}"
        if self.class.method_defined? attr
          reader = attr
        end

        "#{RETURN_OBJECT}[#{const_name}] = #{reader}"
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
        serializer = association.create_serializer Object.const_get(association.serializer.name)

        instance_variable_set serializer_instance_variable, serializer

        "#{RETURN_OBJECT}[#{const_name}] = #{serializer_instance_variable}.serialize object.#{association.name}"
      end.join("\n")
    end

    def filter keys
      if not @only.empty?
        return keys & @only
      end

      if not @except.empty?
        return keys - @except
      end

      keys
    end
  end
end
