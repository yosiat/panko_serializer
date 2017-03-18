module Panko
  class ArraySerializer
    attr_accessor :subjects

    def initialize subjects, options = {}
      @subjects = subjects
      @each_serializer = options[:each_serializer]

			@serializer_instance = @each_serializer.new
      build_reader
    end

		def serializable_object
			serialize @subjects
		end

private
    def build_reader
      reader_method_body = <<-EOMETHOD
        def serialize subjects
					subjects.map { |item| @serializer_instance.serialize item }
        end
      EOMETHOD

      instance_eval reader_method_body, __FILE__, __LINE__
    end
  end
end
