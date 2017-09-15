# frozen_string_literal: true

module Panko
  class ArraySerializer
    attr_accessor :subjects

    def initialize(subjects, options = {})
      @subjects = subjects
      @each_serializer = options[:each_serializer]


      serializer_options = {
        only: options.fetch(:only, []),
        except: options.fetch(:except, [])
      }

      @descriptor = SerializationDescriptorBuilder.build(@each_serializer, serializer_options)
      @context = options.fetch(:context, nil)
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
      writer = Oj::StringWriter.new(mode: :rails)
      Panko::serialize_subjects(subjects.to_a, writer, @descriptor, @context)
      writer.to_s
    end
  end
end
