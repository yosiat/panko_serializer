# frozen_string_literal: true

require_relative "../code_gen"
require_relative "descriptor_builder"
require_relative "serializer_cache"
require_relative "filter_adapter"

module Panko
  module CodeGen
    # Runtime entry point that serializes through the code-gen engine. The
    # shallow seam replacing Panko's C extension (plan slice 2.4): the DSL is
    # unchanged, but +serialize+ / +serialize_to_json+ route here instead of
    # into +Panko.serialize_object+ / +Panko.serialize_objects+.
    #
    # Every call — filtered or not — uses the compiled class from
    # {SerializerCache}. Constructor +only+/+except+ (and a +filters_for+ class
    # method) are translated by {FilterAdapter} into the engine's runtime
    # +Filter+ shape and passed as +filters:+, so a filtered serialization reuses
    # the cached Generated Class instead of recompiling a narrowed descriptor
    # (plan slice 3.1). Statically-declared association filters (+has_many :x,
    # only: [...]+) stay baked into the cached Descriptor at DSL time.
    module Runtime
      module_function

      # @return [String, Hash] JSON string for output: :json, a Hash for :hash
      def serialize_one(serializer_class, record, output:, context: nil, scope: nil, only: nil, except: nil)
        cached(serializer_class, output).serialize_one(
          record, context: context, scope: scope,
          filters: runtime_filters(serializer_class, context, scope, only, except)
        )
      end

      # @return [String, Array<Hash>] JSON array string for :json, Array for :hash
      def serialize_many(serializer_class, records, output:, context: nil, scope: nil, only: nil, except: nil)
        cached(serializer_class, output).serialize_many(
          records, context: context, scope: scope,
          filters: runtime_filters(serializer_class, context, scope, only, except)
        )
      end

      # Returns a fresh generated-class instance ready to serialize. A fresh
      # instance per call keeps the per-call +@object+/+@context+/+@scope+ (set
      # by +_write_one+) isolated across concurrent serializations. The
      # constructor needs the Descriptor to build child serializers for
      # associations, so it is threaded through from the cache.
      def cached(serializer_class, output)
        SerializerCache.fetch(serializer_class, output: output)
          .new(descriptor: SerializerCache.descriptor_for(serializer_class))
      end

      # Resolves the effective +only+/+except+ and translates them into the
      # engine's runtime +Filter+ shape. A serializer's +filters_for(context,
      # scope)+ overrides the constructor filters per key (matching Panko's
      # +options.merge!(filters_for(...))+). Returns +nil+ when nothing is
      # filtered so the Generated Class takes +Filter::NONE+'s allocation-free
      # path.
      def runtime_filters(serializer_class, context, scope, only, except)
        only, except = with_filters_for(serializer_class, context, scope, only, except)
        return nil if blank?(only) && blank?(except)
        FilterAdapter.to_engine_filters(blank?(only) ? nil : only, blank?(except) ? nil : except)
      end

      def with_filters_for(serializer_class, context, scope, only, except)
        return [only, except] unless serializer_class.respond_to?(:filters_for)
        overrides = serializer_class.filters_for(context, scope) || {}
        [overrides.fetch(:only, only), overrides.fetch(:except, except)]
      end

      def blank?(filter)
        filter.nil? || (filter.respond_to?(:empty?) && filter.empty?)
      end
    end
  end
end
