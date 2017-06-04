module Panko
  class HasOneAttribute
    def initialize(name, options)
      @name = name

      @options = options.dup
      @serializer = options.delete(:serializer)
    end

    attr_reader :name, :serializer

    def create_serializer(serializer_const, options={})
      serializer_options = {
        context: options[:context],
        except: options.fetch(:except, []) + @options.fetch(:except, []),
        only: options.fetch(:only, []) + @options.fetch(:only, [])
      }

      serializer_const.new serializer_options
    end
  end
end
