# frozen_string_literal: true

require_relative "../code_gen"
require_relative "serializer_cache"
require_relative "filter_adapter"

module Panko
  module CodeGen
    module Runtime
      module_function

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
