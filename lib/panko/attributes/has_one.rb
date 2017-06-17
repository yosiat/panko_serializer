module Panko
  class HasOneAttribute < BaseAttribute
    def initialize(name, options)
      super(name)

      @options = options.dup
      @serializer = options.delete(:serializer)
    end

    attr_reader :serializer

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
