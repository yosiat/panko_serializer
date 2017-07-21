module Panko
  class RelationshipAttribute < BaseAttribute
    def initialize(name, options)
      super(name)

      @options = options.dup

      @serializer = options.delete(:serializer)
      @serializer_const = Object.const_get(serializer.name)
      @serializer_name = "@#{name}_serializer".freeze

      @code = build_code
    end

    attr_reader :serializer, :serializer_name, :code

    def const_value
      @name.to_s
    end

    def const_name
      const_value.upcase
    end


    def build_code
      output = "writer.push_key(#{const_name}) \n"
      output << "#{serializer_name}.serialize_to_writer(object.#{name}, writer)"
    end

    def serializer_options(options)
      {
        context: options[:context],
        except: options.fetch(:except, []) + @options.fetch(:except, []),
        only: options.fetch(:only, []) + @options.fetch(:only, [])
      }
    end

    def create_serializer(options={})
      raise Error, "Hello"
    end
  end
end
