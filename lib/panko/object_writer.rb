module Panko
  class ObjectWriter
    attr_reader :output

    def initiailize
      @output = nil

      @current_pushed_type = nil
      @last_pushed_type = nil
    end

    def push_array
      @output = [] if @output.nil?

      @last_pushed_type = @current_pushed_type
      @current_pushed_type = :array
    end

    def push_object
      @output = {} if @output.nil?
      @output << {} if @output.is_a? Array

      if @current_pushed_type == :key
        pushed_key = @output.keys.last
        @output[pushed_key] = {}
      end

      @last_pushed_type = @current_pushed_type
      @current_pushed_type = :object
    end

    def push_value(value, key=nil)
      if @current_pushed_type == :object
        cursor = @output if @output.is_a? Hash
        cursor = @output.last if @output.is_a? Array

        if @last_pushed_type == :key
          pushed_key = cursor.keys.last
          cursor[pushed_key][key] = value
        else
          cursor[key] = value
        end
      end

      if @current_pushed_type == :key
        cursor = @output if @output.is_a? Hash
        cursor = @output.last if @output.is_a? Array

        pushed_key = cursor.keys.last
        cursor[pushed_key] = value
      end

      if @current_pushed_type == :array
        @output << value
      end
    end

    def push_key(key)
      if @current_pushed_type == :object
        cursor = @output if @output.is_a? Hash
        cursor = @output.last if @output.is_a? Array

        @last_pushed_type = @current_pushed_type
        @current_pushed_type = :key

        cursor[key] = nil
      end
    end

    def pop
    end
  end
end
