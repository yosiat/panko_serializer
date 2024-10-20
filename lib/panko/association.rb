# frozen_string_literal: true

module Panko
  class Association
    attr_reader :name_sym, :name_str, :descriptor
    attr_writer :descriptor

    def initialize(name_sym, name_str, descriptor)
      @name_sym = name_sym
      @name_str = name_str
      @descriptor = descriptor
    end

    def serializer_writer
      @serializer_writer ||= Impl::Serializer.new(@descriptor)
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
