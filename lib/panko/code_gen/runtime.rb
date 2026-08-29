# frozen_string_literal: true

require_relative "../code_gen"
require_relative "serializer_cache"
require_relative "filter_adapter"

module Panko
  module CodeGen
    # Shared runtime pieces of the seam replacing Panko's C extension. The
    # serialize entry points live inline in +Panko::Serializer+ /
    # +Panko::ArraySerializer+ (each checks a Generated Class instance out of
    # {SerializerCache.instance_pool} around the call); what they share —
    # translating +only+/+except+/+filters_for+ into the engine's runtime
    # +Filter+ shape via {FilterAdapter} — lives here. Statically-declared
    # association filters (+has_many :x, only: [...]+) stay baked into the
    # cached Descriptor at DSL time.
    module Runtime
      module_function

      # Resolves the effective +only+/+except+ and translates them into the
      # engine's runtime +Filter+ shape. A serializer's +filters_for(context,
      # scope)+ overrides the constructor filters per key (matching Panko's
      # +options.merge!(filters_for(...))+). Returns +nil+ when nothing is
      # filtered so the Generated Class takes +Filter::None+'s allocation-free
      # path — and allocates nothing itself on that path (it sits on every
      # unfiltered serialize).
      def runtime_filters(serializer_class, context, scope, only, except)
        if serializer_class.respond_to?(:filters_for)
          overrides = serializer_class.filters_for(context, scope) || {}
          only = overrides.fetch(:only, only)
          except = overrides.fetch(:except, except)
        end
        return nil if blank?(only) && blank?(except)
        FilterAdapter.to_engine_filters(blank?(only) ? nil : only, blank?(except) ? nil : except)
      end

      def blank?(filter)
        filter.nil? || (filter.respond_to?(:empty?) && filter.empty?)
      end
    end
  end
end
