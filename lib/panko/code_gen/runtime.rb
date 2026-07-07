# frozen_string_literal: true

require_relative "../code_gen"
require_relative "descriptor_builder"
require_relative "serializer_cache"

module Panko
  module CodeGen
    # Runtime entry point that serializes through the code-gen engine. The
    # shallow seam replacing Panko's C extension (plan slice 2.4): the DSL is
    # unchanged, but +serialize+ / +serialize_to_json+ route here instead of
    # into +Panko.serialize_object+ / +Panko.serialize_objects+.
    #
    # Unfiltered calls use the compiled class from {SerializerCache}. Filtered
    # calls (constructor +only+/+except+ or a +filters_for+ class method) still
    # go through Panko's existing +SerializationDescriptor.build+ — which
    # applies the filters by narrowing the descriptor — and compile that
    # narrowed descriptor per call. Moving filters onto the engine's runtime
    # +Filter+ (so filtered calls hit the cache too) is Phase 3.2; Phase 2 is a
    # correctness milestone, so the per-call compile for filtered calls is
    # accepted for now.
    module Runtime
      module_function

      # @return [String, Hash] JSON string for output: :json, a Hash for :hash
      def serialize_one(serializer_class, record, output:, context: nil, scope: nil, only: nil, except: nil)
        generated(serializer_class, output, context, scope, only, except)
          .serialize_one(record, context: context, scope: scope, filters: nil)
      end

      # @return [String, Array<Hash>] JSON array string for :json, Array for :hash
      def serialize_many(serializer_class, records, output:, context: nil, scope: nil, only: nil, except: nil)
        generated(serializer_class, output, context, scope, only, except)
          .serialize_many(records, context: context, scope: scope, filters: nil)
      end

      # Returns a fresh generated-class instance ready to serialize. A fresh
      # instance per call keeps the per-call +@object+/+@context+/+@scope+ (set
      # by +_write_one+) isolated across concurrent serializations. The
      # constructor needs the Descriptor to build child serializers for
      # associations, so it is threaded through from the cache.
      def generated(serializer_class, output, context, scope, only, except)
        if unfiltered?(serializer_class, only, except)
          SerializerCache.fetch(serializer_class, output: output)
            .new(descriptor: SerializerCache.descriptor_for(serializer_class))
        else
          descriptor = build_filtered_descriptor(serializer_class, context, scope, only, except)
          Panko::CodeGen.compile(descriptor, output: output, config: Config.new).new(descriptor: descriptor)
        end
      end

      def unfiltered?(serializer_class, only, except)
        blank?(only) && blank?(except) && !serializer_class.respond_to?(:filters_for)
      end

      def build_filtered_descriptor(serializer_class, context, scope, only, except)
        options = {context: context, scope: scope}
        options[:only] = only unless blank?(only)
        options[:except] = except unless blank?(except)
        DescriptorBuilder.from_panko_descriptor(
          Panko::SerializationDescriptor.build(serializer_class, options)
        )
      end

      def blank?(filter)
        filter.nil? || (filter.respond_to?(:empty?) && filter.empty?)
      end
    end
  end
end
