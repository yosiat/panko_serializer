# frozen_string_literal: true

require_relative "../code_gen"

module Panko
  module CodeGen
    # Translates Panko's +only:+/+except:+ filters into the engine's runtime Filter shape.
    module FilterAdapter
      module_function

      def to_engine_filters(only, except)
        only_attrs, only_assocs = split(only)
        except_attrs, except_assocs = split(except)

        result = {}
        merge_level!(result, only_attrs, except_attrs)

        (only_assocs.keys | except_assocs.keys).each do |source|
          result[source] = to_engine_filters(only_assocs[source], except_assocs[source])
        end

        result
      end

      def split(filter)
        case filter
        when nil then [[], {}]
        when ::Array then [filter, {}]
        when ::Hash then [Array(filter[:instance]), filter.except(:instance)]
        else raise ArgumentError, "filters must be an Array or Hash, got #{filter.class}"
        end
      end

      # Filter.wrap raises when one level has both :only and :except, so both fold into :only.
      def merge_level!(result, only_attrs, except_attrs)
        if !only_attrs.empty?
          result[:only] = only_attrs - except_attrs
        elsif !except_attrs.empty?
          result[:except] = except_attrs
        end
      end
    end
  end
end
