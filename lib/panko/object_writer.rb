
module Panko
  class ObjectWriter
    attr_reader :output

    def initiailize
      @output = nil
      @current_pushed_type = nil
    end

    def push_array
      @output = [] if @output.nil?
      @current_pushed_type = :array
    end

    def push_object
      @output = {} if @output.nil?
      @output << {} if @output.is_a? Array

      @current_pushed_type = :object
    end

    def push_value(value, key=nil)
      if @current_pushed_type == :object
        cursor = @output if @output.is_a? Hash
        cursor = @output.last if @output.is_a? Array
        cursor[key] = value
      end

      if @current_pushed_type == :array
        @output << value
      end
    end

    def pop
    end
  end
end
