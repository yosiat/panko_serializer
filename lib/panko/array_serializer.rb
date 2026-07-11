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
    # the serializer class's own slot without a dispatch-layer hop. Pool
    # selection dispatches on the first record's class through the same
    # one-entry inline cache as Panko::Serializer — an empty array's
    # NilClass pins to the generic pool, and a heterogeneous tail is safe
    # because a specialized variant guards per record and delegates
    # mismatches to its generic twin.

    def serialize(subjects)
      each_serializer = @each_serializer
      records = subjects.to_a
      model = records.first.class
      cached = each_serializer._cg_last_hash
      pool = if cached && model.equal?(cached[0])
        cached[1]
      else
        Panko::CodeGen::SerializerCache.variant_pool(each_serializer, :hash, model)
      end
      filters = if @only || @except || each_serializer._cg_has_filters_for
        Panko::CodeGen::Runtime.runtime_filters(each_serializer, @context, @scope, @only, @except)
      end
      stack = pool.stack
      instance = stack.pop || pool.build
      begin
        instance.serialize_many(records, context: @context, scope: @scope, filters: filters)
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
      records = subjects.to_a
      model = records.first.class
      cached = each_serializer._cg_last_json
      pool = if cached && model.equal?(cached[0])
        cached[1]
      else
        Panko::CodeGen::SerializerCache.variant_pool(each_serializer, :json, model)
      end
      filters = if @only || @except || each_serializer._cg_has_filters_for
        Panko::CodeGen::Runtime.runtime_filters(each_serializer, @context, @scope, @only, @except)
      end
      stack = pool.stack
      instance = stack.pop || pool.build
      begin
        instance.serialize_many(records, context: @context, scope: @scope, filters: filters)
      ensure
        instance._release
        stack.push(instance)
      end
    end
  end
end
