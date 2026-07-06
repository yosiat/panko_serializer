# frozen_string_literal: true

module Fixtures
  module ConfigNullForHasOneOff
    INNER_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ConfigNullForHasOneOffInnerSerializer",
      models: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [],
      associations: []
    )

    CONFIG = Panko::CodeGen::Config.new(null_for_missing_has_one: false)
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ConfigNullForHasOneOffSerializer",
      models: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id)
      ],
      method_attributes: [],
      associations: [
        Panko::CodeGen::Association.new(
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
