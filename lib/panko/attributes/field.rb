module Panko
  class FieldAttribute < BaseAttribute
    def initialize(name)
      super

      @read_call = build_read_call
      @method_call = build_method_call
    end

    attr_reader :read_call, :method_call

    def build_read_call
      reader = "object.#{name}"
      "writer.push_value(#{reader}, #{const_name})"
    end

    def build_method_call
      "writer.push_value(#{name}, #{const_name})"
    end
  end
end
