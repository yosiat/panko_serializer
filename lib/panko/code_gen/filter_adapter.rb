# frozen_string_literal: true

require_relative "../code_gen"

module Panko
  module CodeGen
    # Translates Panko's constructor filter shape into the engine's runtime
    # Filter shape so a filtered serialize can pass `filters:` to the cached
    # Generated Class (Filter.wrap + child threading) instead of recompiling a
    # descriptor narrowed by SerializationDescriptor#apply_filters.
    #
    # Panko shape (per level): only:/except: are each an Array of filter keys
    # (a value field's output name; an association's declared name), or a Hash
    # using :instance for the current level and reader/source symbols
    # for association sub-filters. Empty Arrays mean "no filter". When only and
    # except are both supplied, Panko selects(only) then rejects(except), so the
    # effective whitelist is only - except.
    #
    # Engine shape (per level, per docs/code_gen/code_gen filters): {only: [...], except:
    # [...], <source> => <sub-hash>}. :only and :except must not co-exist at one
    # level (Filter.wrap raises), so co-supply is folded into :only. Association
    # sub-filters are keyed by Source symbol, matching Filter#child(:<source>).
    module FilterAdapter
      module_function

      # @param only [Array, Hash, nil] Panko's constructor `only:`
      # @param except [Array, Hash, nil] Panko's constructor `except:`
      # @return [Hash] engine-shaped filters; an empty Hash means no filtering
      #   (Filter.wrap collapses it to Filter::None)
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

      # Splits a Panko filter value into [current-level Array, association Hash].
      # A bare Array is the current level with no association filters; a Hash
      # takes its current level from :instance and treats every other key as an
      # association sub-filter. nil is the empty filter.
      def split(filter)
        case filter
        when nil then [[], {}]
        when ::Array then [filter, {}]
        when ::Hash then [Array(filter[:instance]), filter.except(:instance)]
        else raise ArgumentError, "filters must be an Array or Hash, got #{filter.class}"
        end
      end

      # Writes the current level's :only/:except into +result+. :only wins over
      # :except (Panko's select-then-reject == only - except). A non-empty only
      # always emits :only even when the difference is empty (Panko then keeps no
      # fields, which the engine expresses as an empty whitelist). Absent filters
      # emit nothing so the level collapses to Filter::None.
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
