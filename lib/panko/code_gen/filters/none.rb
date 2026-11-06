# frozen_string_literal: true

module Panko::CodeGen
  module Filter
    # Takes the same arguments as +Indexed::Array+ so generated code calls
    # one shape whether or not filters were given.
    module None
      def self.drops?(_index)
        false
      end

      def self.child(_source, _field_index)
        self
      end

      freeze
    end
  end
end
