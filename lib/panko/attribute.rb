# frozen_string_literal: true

module Panko
  class Attribute
    attr_reader :name, :name_sym
    attr_accessor :type, :cached_writer, :alias_name

    def initialize(name, alias_name = nil)
      # TODO: validate name & alias_name are strings

      self.name = name
      @alias_name = alias_name

      @type = nil
      @cached_writer = nil
    end

    def self.create(name, alias_name: nil)
      alias_name = alias_name.to_s unless alias_name.nil?
      Attribute.new(name.to_s, alias_name)
    end

    def ==(other)
      return name_sym == other if other.is_a? Symbol
      return @name == other.name && @alias_name == other.alias_name if other.is_a? Panko::Attribute

      super
    end

    def invalidate!
      @type = nil
      @cached_writer = nil
    end

    def hash
      @name_sym.hash
    end

    def name_for_serialization
      return @alias_name unless @alias_name.nil?
      @name
    end

    def eql?(other)
      self.==(other)
    end

    def inspect
      "<Panko::Attribute name=#{@name.inspect} alias_name=#{@alias_name.inspect}>"
    end

    def name=(name)
      @name = name
      @name_sym = name.to_sym
    end
  end
end
