module Panko
  class ArraySerializer
    attr_accessor :subjects

    def initialize subjects, options = {}
      @subjects = subjects
      @each_serializer = options[:each_serializer]

			@serializer_instance = @each_serializer.new
    end

		def serializable_object
			serialize @subjects
		end

		def serialize subjects
			subjects.map { |item| @serializer_instance.serialize item }
		end

  end
end
