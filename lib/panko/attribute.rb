# frozen_string_literal: true

module Panko
  class Attribute
    attr_reader :name, :name_sym, :alias_name
    attr_accessor :type

    def initialize(name, alias_name = nil)
      # TODO: validate name & alias_name are strings

      self.name = name
      @alias_name = alias_name

      @type = nil
      @record_class = nil
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

    # TODO: this logic is specific to ActiveRecord attributes writer and shouldn't be here.
    def invalidate!(new_object_class)
      return if @record_class == new_object_class

      @type = nil
      @record_class = new_object_class

      # Once the record class is changed for this attribute, check if
      # we attribute_aliases (from ActivRecord), if so fill in
      # performance wise - this code should be called once (unless the serialzier
      # is polymorphic)
      aliases_hash = @record_class.attribute_aliases
      return if aliases_hash.empty?

      aliased_value = aliases_hash[@name]
      if aliased_value.present?
        @alias_name = @name
        self.name = aliased_value
      end
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

    private

    def name=(name)
      @name = name
      @name_sym = name.to_sym
    end
  end
end
