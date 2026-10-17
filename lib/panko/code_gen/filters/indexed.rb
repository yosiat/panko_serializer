# frozen_string_literal: true

module Panko::CodeGen
  module Filter
    module Indexed
      module_function

      def build(hash, field_index)
        n = field_index.size
        only = hash[:only]
        except = hash[:except]
        only_set = only&.to_set
        except_set = except&.to_set

        arr = ::Array.new(n)
        field_index.each do |name, i|
          arr[i] = drop?(name, only_set, except_set)
        end
        Array.new(hash, arr)
      end

      def drop?(name, only_set, except_set)
        if only_set
          !only_set.include?(name)
        elsif except_set
          except_set.include?(name)
        else
          false
        end
      end

      class Array
        def initialize(hash, drops_array)
          @hash = hash
          @drops_array = drops_array
          @children_cache = {}
        end

        def drops?(index)
          @drops_array[index]
        end

        # Each cached entry keeps the +field_index+ it was built for (checked with
        # +equal?+): two Associations may share a Source but nest different classes.
        def child(source, field_index)
          cached = @children_cache[source]
          return cached[1] if cached && cached[0].equal?(field_index)
          resolved = Indexed.resolve_child(@hash, source, field_index)
          @children_cache[source] = [field_index, resolved]
          resolved
        end
      end

      # +Filter.wrap+ already validated every nested level, so no re-check here.
      def resolve_child(hash, source, field_index)
        sub = hash[source]
        return None unless sub.is_a?(Hash) && !sub.empty?
        build(sub, field_index)
      end
    end
  end
end
