# frozen_string_literal: true

class Panko::ObjectWriter
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
    unless @next_key.nil?
      raise "push_value is called with key after push_key is called" unless key.nil?
      key = @next_key
      @next_key = nil
    end

    @values.last[key] = value.as_json
  end

  def push_json(value, key = nil)
    if value.is_a?(String)
      value = Oj.load(value) rescue nil
    end

    push_value(value, key)
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

  def output
    raise "Output is called before poping all" unless @values.empty?
    @output
  end
end
