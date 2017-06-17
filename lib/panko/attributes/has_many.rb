module Panko
  class HasManyAttribute < BaseAttribute
    def initialize(name, options)
      super(name)

      @options = options.dup
      @serializer = @options.delete(:serializer)
    end

    attr_reader :serializer

    def create_serializer(serializer_const, options={})
      serializer_options = {
        context: options[:context],
        each_serializer: serializer_const,
        except: options.fetch(:except, []) + @options.fetch(:except, []),
        only: options.fetch(:only, []) + @options.fetch(:only, [])
      }

      Panko::ArraySerializer.new([], serializer_options)
    end
  end
end
