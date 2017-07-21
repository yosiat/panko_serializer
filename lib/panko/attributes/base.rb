module Panko
  class BaseAttribute
    def initialize(name)
      @name = name
    end

    attr_reader :name
  end
end
