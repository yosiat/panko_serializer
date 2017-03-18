module Panko
  class HasOneAttribute
    def initialize name, serializer
      @name = name
      @serializer = serializer
    end

    attr_reader :name, :serializer

    def create_serializer serializer_const
      serializer_const.new
    end
  end
end
