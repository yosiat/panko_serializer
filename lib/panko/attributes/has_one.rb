module Panko
  class HasOneAttribute
    def initialize name, options
      @name = name

      @options = options.dup
      @serializer = options.delete(:serializer)
    end

    attr_reader :name, :serializer

    def create_serializer serializer_const, context
      serializer_const.new @options.merge(context: context)
    end
  end
end
