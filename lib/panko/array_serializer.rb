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

    # Inlined checkout/checkin for the same reason as Panko::Serializer's
    # serialize methods: the mode is static per method, so the pool comes off
    # the serializer class's own slot without a dispatch-layer hop.

    def serialize(subjects)
      each_serializer = @each_serializer
      pool = each_serializer._cg_pool_hash ||
        Panko::CodeGen::SerializerCache.instance_pool(each_serializer, :hash)
      filters = if @only || @except || each_serializer._cg_has_filters_for
        Panko::CodeGen::Runtime.runtime_filters(each_serializer, @context, @scope, @only, @except)
      end
      stack = pool.stack
      instance = stack.pop || pool.build
      begin
        instance.serialize_many(subjects.to_a, context: @context, scope: @scope, filters: filters)
      ensure
        # See Panko::Serializer#serialize — a pooled instance must not pin
        # the last record graph between calls.
        instance._release
        stack.push(instance)
      end
    end

    def to_a
      serialize(@subjects)
    end

    def serialize_to_json(subjects)
      each_serializer = @each_serializer
      pool = each_serializer._cg_pool_json ||
        Panko::CodeGen::SerializerCache.instance_pool(each_serializer, :json)
      filters = if @only || @except || each_serializer._cg_has_filters_for
        Panko::CodeGen::Runtime.runtime_filters(each_serializer, @context, @scope, @only, @except)
      end
      stack = pool.stack
      instance = stack.pop || pool.build
      begin
        instance.serialize_many(subjects.to_a, context: @context, scope: @scope, filters: filters)
      ensure
        instance._release
        stack.push(instance)
      end
    end
  end
end
