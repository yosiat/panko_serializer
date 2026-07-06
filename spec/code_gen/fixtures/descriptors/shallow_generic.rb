# frozen_string_literal: true

module Fixtures
  module ShallowGeneric
    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ShallowGenericSerializer",
      models: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :title, source: :title)
      ],
      method_attributes: [],
      associations: []
    )
    MODES = %i[json hash]

    def self.sanity_record
      {"id" => 1, "title" => "hi"}
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"id":1,"title":"hi"}'
      when :hash then {"id" => 1, "title" => "hi"}
      end
    end
  end
end
