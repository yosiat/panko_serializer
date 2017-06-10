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

    def to_json
      serialize_to_json @subjects
    end

    def serialize(subjects)
      Oj.load(serialize_to_json(subjects))
    end

    def to_a
      Oj.load(serialize_to_json(@subjects))
    end

    def serialize_to_json(subjects)
      writer = Oj::StringWriter.new(indent: 0, mode: :rails)
      serialize_to_writer subjects, writer
      writer.to_s
    end


    #
    # Internal API
    #
    def serialize_to_writer(subjects, writer)
      writer.push_array

      subjects.to_a.each do |item|
        @serializer_instance.serialize_to_writer(item, writer)
      end

      writer.pop
    end
  end
end
