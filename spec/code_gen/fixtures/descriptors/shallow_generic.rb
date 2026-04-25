# frozen_string_literal: true

module Fixtures
  module ShallowGeneric
    CONFIG = SerializersCodeGen::Config.new
    DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ShallowGenericSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :title, source: :title)
      ],
      method_attributes: [],
      associations: []
    )
    MODES = [:json]

    def self.sanity_record
      {"id" => 1, "title" => "hi"}
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"id":1,"title":"hi"}'
      end
    end
  end
end
