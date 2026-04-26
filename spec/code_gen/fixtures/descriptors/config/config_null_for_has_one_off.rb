# frozen_string_literal: true

module Fixtures
  module ConfigNullForHasOneOff
    INNER_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ConfigNullForHasOneOffInnerSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [],
      associations: []
    )

    CONFIG = SerializersCodeGen::Config.new(null_for_missing_has_one: false)
    DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ConfigNullForHasOneOffSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id)
      ],
      method_attributes: [],
      associations: [
        SerializersCodeGen::Association.new(
          name: :inner,
          kind: :has_one,
          descriptor: INNER_DESCRIPTOR
        )
      ]
    )
    MODES = %i[json]

    def self.sanity_record
      {"id" => 1, "inner" => nil}
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"id":1}'
      end
    end
  end
end
