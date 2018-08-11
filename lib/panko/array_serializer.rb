# frozen_string_literal: true

module Panko
  class ArraySerializer
    attr_accessor :subjects

    def initialize(subjects, options = {})
      @subjects = subjects
      @each_serializer = options[:each_serializer]

      if @each_serializer.nil?
        raise ArgumentError, %{
Please pass valid each_serializer to ArraySerializer, for example:
> Panko::ArraySerializer.new(posts, each_serializer: PostSerializer)
        }
      end

      serializer_options = {
        only: options.fetch(:only, []),
        except: options.fetch(:except, []),
        context: options[:context],
        scope: options[:scope]
      }

      @serialization_context = SerializationContext.create(options)
      @descriptor = Panko::SerializationDescriptor.build(@each_serializer, serializer_options, @serialization_context)
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
      Panko.serialize_subjects(subjects.to_a, writer, @descriptor)
      @descriptor.set_serialization_context(nil) unless @serialization_context.is_a?(EmptySerializerContext)
      writer.to_s
    end
  end
end
