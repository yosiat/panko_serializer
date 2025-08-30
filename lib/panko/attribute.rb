# frozen_string_literal: true

module Panko
  class Attribute < Data.define(:name, :alias_name, :name_sym, :name_str, :ivar_name, :type, :record_class)
    def self.create(name, alias_name: nil)
      name_str = name.to_s.freeze
      alias_name_str = alias_name&.to_s&.freeze
      name_sym = name.to_sym
      ivar_name = "@#{name_str}".freeze

      new(
        name: name_str,
        alias_name: alias_name_str,
        name_sym: name_sym,
        name_str: name_str,
        ivar_name: ivar_name,
        type: nil,
        record_class: nil
      )
    end

    def ==(other)
      return name_sym == other if other.is_a? Symbol
      return name == other.name && alias_name == other.alias_name if other.is_a? Panko::Attribute
      super
    end

    def hash
      name_sym.hash
    end

    def eql?(other)
      self.==(other)
    end

    def inspect
      "<Panko::Attribute name=#{name.inspect} alias_name=#{alias_name.inspect}>"
    end
  end
end
