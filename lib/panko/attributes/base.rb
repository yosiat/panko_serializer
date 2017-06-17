module Panko
  class BaseAttribute
    def initialize(name)
      @name = name

      @const_value = @name.to_s
      @const_name = @const_value.upcase

      @serializer_name = "@#{name}_serializer".freeze
    end

    attr_reader :name, :const_name, :const_value, :serializer_name
  end
end
