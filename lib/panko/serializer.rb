module Panko
  class Serializer
    class << self
      def inherited(base)
        base._attributes = (_attributes || []).dup
        base._associations = (_associations || []).dup

        @_attributes = []
        @_associations = []
      end

      attr_accessor :_attributes, :_associations, :_associations_serializers

      def attributes *attrs
        @_attributes.concat attrs

        build_attributes_reader
        #build_associations_reader
      end


      def has_one name, options
        serializer = options[:serializer]

        @_associations << [name, :has_one, serializer]

        build_associations_reader
      end

      def has_many name, options
        serializer = options[:serializer]

        @_associations << [name, :has_many, serializer]

        build_associations_reader
      end

      private

      def build_associations_reader
        return_object = "obj"

        setters = @_associations.map do |association|
          name, type, serializer = association

          # memoize the key
          const_set name.upcase, name.to_s.freeze

          if type == :has_one
            <<-EOMETHOD
              @#{name}_serializer = #{serializer.name}.new unless defined? @#{name}_serializer
              @#{name}_serializer.subject = subject.#{name}
              #{return_object}[#{name.upcase}] = @#{name}_serializer.serializable_object
            EOMETHOD
          end

          if type == :has_many
            <<-EOMETHOD
              @#{name}_serializer = Panko::ArraySerializer.new([], each_serializer: #{serializer.name}) unless defined? @#{name}_serializer
              @#{name}_serializer.subjects = subject.#{name}
              #{return_object}[#{name.upcase}] = @#{name}_serializer.serializable_object
            EOMETHOD
          end
        end.join "\n"

        associations_reader_method_body = <<-EOMETHOD
          def read_associations  obj
            #{setters}
          end
        EOMETHOD

        class_eval associations_reader_method_body, __FILE__, __LINE__
      end

      def build_attributes_reader
        setters = @_attributes.map do |attr|
          const_set attr.upcase, attr.to_s.freeze

          reader = "subject.#{attr}"

          "obj[#{attr.upcase}] = #{reader}"
          "obj[\"#{attr}\"] = #{reader}"
        end.join "\n"

        attributes_reader_method_body = <<-EOMETHOD
          def read_attributes obj
            #{setters}
          end
        EOMETHOD



        class_eval attributes_reader_method_body, __FILE__, __LINE__
      end
    end

    attr_accessor :subject

    def read_associations obj
    end


    def serializable_object obj={}
      read_attributes obj
      read_associations obj unless self.class._associations.empty?
      obj
    end
  end
end
