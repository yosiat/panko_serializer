# frozen_string_literal: true

require_relative "code_gen/runtime"

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

      @context = options[:context]
      @scope = options[:scope]
      @only = options[:only]
      @except = options[:except]
    end

    def to_json
      serialize_to_json(@subjects)
    end

    def serialize(subjects)
      Panko::CodeGen::Runtime.serialize_many(
        @each_serializer, subjects.to_a, output: :hash,
        context: @context, scope: @scope, only: @only, except: @except
      )
    end

    def to_a
      serialize(@subjects)
    end

    def serialize_to_json(subjects)
      Panko::CodeGen::Runtime.serialize_many(
        @each_serializer, subjects.to_a, output: :json,
        context: @context, scope: @scope, only: @only, except: @except
      )
    end
  end
end
