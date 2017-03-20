module Panko
  class HasManyAttribute
    def initialize name, options
      @name = name

      @options = options.dup
      @serializer = @options.delete(:serializer)
    end

    attr_reader :name, :serializer

    def create_serializer serializer_const, context
      Panko::ArraySerializer.new([], @options.merge(each_serializer: serializer_const, context: context))
    end
  end
end
