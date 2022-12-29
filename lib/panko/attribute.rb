# frozen_string_literal: true

module Panko
  class Attribute
    def self.create(name, alias_name: nil)
      alias_name = alias_name.to_s unless alias_name.nil?
      Attribute.new(name.to_s, alias_name)
    end

    def ==(other)
      return name.to_sym == other if other.is_a? Symbol
      return name == other.name && alias_name == other.alias_name if other.is_a? Panko::Attribute

      super
    end

    def hash
      name.to_sym.hash
    end

    def eql?(other)
      self.==(other)
    end

    def inspect
      "<Panko::Attribute name=#{name.inspect} alias_name=#{alias_name.inspect}>"
    end
  end
end
