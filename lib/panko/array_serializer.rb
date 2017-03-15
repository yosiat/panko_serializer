module Panko
  class ArraySerializer
    attr_accessor :subjects

    def initialize subjects, options = {}
      @subjects = subjects
      @each_serializer = options[:each_serializer]

      build_reader
    end


    def build_reader
      type = @subjects.first.class.name

      reader_method_body = <<-EOMETHOD
        def serializable_object
          serializer = #{@each_serializer}.new

          @subjects.map do |item|
            obj = {}

            serializer.subject = item
            serializer.serializable_object obj
          end
        end
      EOMETHOD

      instance_eval reader_method_body, __FILE__, __LINE__
    end
  end
end
