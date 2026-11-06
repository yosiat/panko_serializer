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

    # Same contract as Panko::Serializer#descriptor.
    def descriptor
      each_serializer = @each_serializer
      filters = if @only || @except || each_serializer._cg_has_filters_for
        Panko::CodeGen::Runtime.runtime_filters(each_serializer, @context, @scope, @only, @except)
      end
      base = Panko::Descriptor.for(each_serializer)
      filters ? Panko::Descriptor::Filtered.new(base, filters) : base
    end

    def serialize(subjects)
      serialize_batch(subjects, :hash) do |instance, records, filters|
        instance.serialize_many(records, context: @context, scope: @scope, filters: filters)
      end
    end

    def to_a
      serialize(@subjects)
    end

    def serialize_to_json(subjects)
      serialize_batch(subjects, :json) do |instance, records, filters|
        instance.serialize_many(records, context: @context, scope: @scope, filters: filters)
      end
    end

    # Writes the array into +writer+ (an +Oj::StringWriter+) as the value of +key+, or as the
    # next element when +key+ is nil. The bytes match what +to_json+ returns.
    def write_json(writer, key = nil)
      serialize_batch(@subjects, :json) do |instance, records, filters|
        instance.serialize_many_to(writer, records, key, context: @context, scope: @scope, filters: filters)
      end
    end

    private

    # The pool is picked by the first record's class. A mixed-class array is
    # safe: a specialized variant hands records of another class to its generic twin.
    def serialize_batch(subjects, mode)
      each_serializer = @each_serializer
      records = subjects.to_a
      model = records.first.class
      cached = (mode == :hash) ? each_serializer._cg_last_hash : each_serializer._cg_last_json
      pool = if cached && model.equal?(cached[0])
        cached[1]
      else
        Panko::CodeGen::SerializerCache.variant_pool(each_serializer, mode, model)
      end
      filters = if @only || @except || each_serializer._cg_has_filters_for
        Panko::CodeGen::Runtime.runtime_filters(each_serializer, @context, @scope, @only, @except)
      end
      stack = pool.stack
      instance = stack.pop || pool.build
      begin
        yield instance, records, filters
      ensure
        instance._release
        stack.push(instance)
      end
    end
  end
end
