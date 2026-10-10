# frozen_string_literal: true

module Panko::CodeGen
  module ActiveRecord
    module DefineAttributeMethods
      def self.ensure!(klass)
        return if klass.attribute_methods_generated?
        klass.define_attribute_methods
        nil
      end
    end
  end
end
