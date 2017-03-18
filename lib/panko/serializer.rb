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

    def serialize subject
      serializable_object subject, {}
    end

private
      def build_associations_reader
        return_object = "obj"

        associations = self.class._associations.map do |association|
          name, type, serializer = association

          self.class.const_set name.upcase, name.to_s.freeze unless self.class.const_defined? name.upcase

          if type == :has_one
						instance_variable_set "@#{name}_serializer", Object.const_get(serializer.name).new

            "#{return_object}[#{name.upcase}] = @#{name}_serializer.serialize subject.#{name}"
          elsif type == :has_many
						array_serializer = Panko::ArraySerializer.new([], each_serializer: Object.const_get(serializer.name))
						instance_variable_set "@#{name}_serializer", array_serializer

            "#{return_object}[#{name.upcase}] = @#{name}_serializer.serialize subject.#{name}"
          end
        end

				associations.join "\n"
      end

      def build_attributes_reader
        setters = self.class._attributes.map do |attr|
          self.class.const_set attr.upcase, attr.to_s.freeze unless self.class.const_defined? attr.upcase

          reader = "subject.#{attr}"
					if self.class.method_defined? attr
						reader = attr
					end

          "obj[#{attr.upcase}] = #{reader}"
        end.join "\n"


        attributes_reader_method_body = <<-EOMETHOD
          def serializable_object subject, obj
            #{setters}
						#{build_associations_reader}
						obj
          end
        EOMETHOD

				# TODO: don't redefine if [attributes+associations] wasn't changed
				instance_eval attributes_reader_method_body, __FILE__, __LINE__
      end
  end
end
