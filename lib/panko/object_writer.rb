require 'oj'

module Panko
  class ObjectWriter
    def initialize
      @w = Oj::StringWriter.new(mode: :rails)
    end

    [:pop_all, :push_array, :push_key, :push_value, :push_object, :pop].each do |method|
      class_eval <<-CODE
        def #{method.to_s}(*args)
          @w.#{method.to_s}(*args)
        end
      CODE
    end

    def output
      Oj.load(@w.to_s)
    end
  end
end
