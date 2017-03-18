module Panko
  class HasManyAttribute
    def initialize name, serializer
      @name = name
      @serializer = serializer
    end

    attr_reader :name, :serializer

    def create_serializer serializer_const
      Panko::ArraySerializer.new([], each_serializer: serializer_const)
    end
  end
end
