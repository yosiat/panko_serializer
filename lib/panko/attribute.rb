# frozen_string_literal: true

module Panko
  class Attribute
    def self.create(name, alias_name: nil)
      alias_name = alias_name.to_s unless alias_name.nil?
      Attribute.new(name.to_s, alias_name)
    end

    def ==(attr)
      return name.to_sym == attr if attr.is_a? Symbol
      if attr.is_a? Panko::Attribute
        return name == attr.name && alias_name == attr.alias_name
      end
      super
    end

    def hash
      name.to_sym.hash
    end

    def eql?(attr)
      self.==(attr)
    end

    def inspect
      "<Panko::Attribute name=#{name.inspect} alias_name=#{alias_name.inspect}>"
    end
  end
end
