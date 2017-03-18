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
        @_associations << [name, :has_one, serializer]
      end

      def has_many name, options
        serializer = options[:serializer]
        @_associations << [name, :has_many, serializer]
      end
    end

    def initialize
      build_attributes_reader
    end

    attr_reader :object

    def serialize object
      serializable_object object, {}
    end

    private

    RETURN_OBJECT = "serialized_object"

    def build_associations_reader

      associations = self.class._associations.map do |association|
        name, type, serializer = association

        constantize_attribute name

        serializer_instance_variable = "@#{name}_serializer"
        serialized_resolved_const = Object.const_get(serializer.name)

        if type == :has_one
          instance_variable_set serializer_instance_variable, serialized_resolved_const.new
        elsif type == :has_many
          array_serializer = Panko::ArraySerializer.new([], each_serializer: serialized_resolved_const)
          instance_variable_set serializer_instance_variable, array_serializer
        end

        "#{RETURN_OBJECT}[#{name.upcase}] = #{serializer_instance_variable}.serialize object.#{name}"
      end

      associations.join "\n"
    end

    def build_attributes_reader
      setters = self.class._attributes.map do |attr|
        constantize_attribute attr

        reader = "object.#{attr}"
        if self.class.method_defined? attr
          reader = attr
        end

        "#{RETURN_OBJECT}[#{attr.upcase}] = #{reader}"
      end.join "\n"


      attributes_reader_method_body = <<-EOMETHOD
        def serializable_object object, #{RETURN_OBJECT}
          @object = object
          #{setters}
          #{build_associations_reader}
          #{RETURN_OBJECT}
        end
      EOMETHOD

      # TODO: don't redefine if [attributes+associations] wasn't changed
      instance_eval attributes_reader_method_body, __FILE__, __LINE__
    end

    def constantize_attribute attr
      return if self.class.const_defined? attr.upcase
      self.class.const_set attr.upcase, attr.to_s.freeze
    end
  end
end
