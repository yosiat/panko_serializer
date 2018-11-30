# frozen_string_literal: true

class Panko::ObjectWriter
  attr_reader :output

  def initialize
    @values = []
    @keys = []

    @next_key = nil
    @output = nil
  end

  def push_object(key = nil)
    @values << {}
    @keys << key
  end

  def push_array(key = nil)
    @values << []
    @keys << key
  end

  def push_key(key)
    @next_key = key
  end

  def push_value(value, key = nil)
    key ||= @next_key

    @values.last[key] = value
    @next_key = nil
  end

  def pop
    result = @values.pop

    if @values.empty?
      @output = result
      return
    end

    scope_key = @keys.pop
    if scope_key.nil?
      @values.last << result
    else
      @values.last[scope_key] = result
    end
  end
end
