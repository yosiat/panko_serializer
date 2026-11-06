# frozen_string_literal: true

module Fixtures
  module ConfigHashOutputKeySymbol
    CONFIG = Panko::CodeGen::Config.new(hash_output_key_type: :symbol)
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "ConfigHashOutputKeySymbolSerializer",
      models: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :name, source: :name)
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
