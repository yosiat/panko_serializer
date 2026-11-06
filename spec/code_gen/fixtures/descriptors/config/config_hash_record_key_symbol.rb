# frozen_string_literal: true

module Fixtures
  module ConfigHashRecordKeySymbol
    CONFIG = Panko::CodeGen::Config.new(hash_record_key_type: :symbol)
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ConfigHashRecordKeySymbolSerializer",
      models: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [],
      associations: []
    )
    MODES = %i[json]

    def self.sanity_record
      {id: 1, name: "Alice"}
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"id":1,"name":"Alice"}'
      end
    end
  end
end
