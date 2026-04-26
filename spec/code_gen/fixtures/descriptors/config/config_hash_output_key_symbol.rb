# frozen_string_literal: true

module Fixtures
  module ConfigHashOutputKeySymbol
    CONFIG = SerializersCodeGen::Config.new(hash_output_key_type: :symbol)
    DESCRIPTOR = SerializersCodeGen::Descriptor.new(
      name: "ConfigHashOutputKeySymbolSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :name, source: :name)
      ],
      method_attributes: [],
      associations: []
    )
    MODES = %i[hash]

    def self.sanity_record
      {"id" => 1, "name" => "Alice"}
    end

    def self.expected_output(mode)
      case mode
      when :hash then {id: 1, name: "Alice"}
      end
    end
  end
end
