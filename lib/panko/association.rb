# frozen_string_literal: true

module Panko
  class Association < Data.define(:name_sym, :name_str, :descriptor)
    def self.new(name, name_str = nil, descriptor = nil)
      name_sym = name.to_sym
      name_str = (name_str || name.to_s).freeze

      super(
        name_sym: name_sym,
        name_str: name_str,
        descriptor: descriptor
      )
    end

    def duplicate
      Panko::Association.new(
        name_sym,
        name_str,
        Panko::SerializationDescriptor.duplicate(descriptor)
      )
    end

    def inspect
      "<Panko::Association name=#{name_str.inspect}>"
    end
  end
end
