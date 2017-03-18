module Panko
  class ArraySerializer
    attr_accessor :subjects

    def initialize subjects, options = {}
      @subjects = subjects
      @each_serializer = options[:each_serializer]


      serializer_options = {
        only: options.fetch(:only, []),
        except: options.fetch(:except, []),
        context: options.fetch(:context, nil)
      }

			@serializer_instance = @each_serializer.new serializer_options
    end

		def serializable_object
			serialize @subjects
		end

		def serialize subjects
      subjects.to_a.map { |item| @serializer_instance.serialize item }
		end
  end
end
