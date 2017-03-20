module Panko
  class FieldAttribute
    def initialize name
      @name = name
    end

    attr_reader :name
  end
end
