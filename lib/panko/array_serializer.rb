module Panko
  class ArraySerializer
    attr_accessor :subjects

    def initialize subjects, options = {}
      @subjects = subjects
      @each_serializer = options[:each_serializer]


      serializer_options = {
        only: options.fetch(:only, []),
        except: options.fetch(:except, []),
        options_builder: options.fetch(:options_builder, nil),
        context: options.fetch(:context, nil)
      }

      @serializer_instance = @each_serializer.new serializer_options
    end

    def serializable_object
      serialize @subjects, Oj::StringWriter.new
    end

    def serialize_to_writer(subjects, writer)
      writer.push_array

      subjects.to_a.each do |item|
        @serializer_instance.serialize_to_writer(item, writer)
      end

      writer.pop
    end

    def serialize(subjects, writer = nil)
      writer ||= Oj::StringWriter.new
      serialize_to_writer subjects, writer
      Oj.load(writer.to_s)
    end
  end
end
