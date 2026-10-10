# frozen_string_literal: true

module Fixtures
  # +Car+ overrides the +make+ column reader, so +make+ must go through the method
  # while +vin+ reads the column directly.
  module StiSpecialized
    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "StiSpecializedSerializer",
      model: Car,
      parent_class: Fixtures::BaseSerializer,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :vin, source: :vin),
        Panko::CodeGen::Attribute.new(name: :make, source: :make)
      ],
      method_attributes: [],
      associations: []
    )
    MODES = %i[json hash]

    def self.sanity_record
      Car.new(id: 1, vin: "ABC123", make: "FORD")
    end

    def self.expected_output(mode)
      case mode
      when :json then '{"vin":"ABC123","make":"Ford"}'
      when :hash
        {
          "vin" => "ABC123",
          "make" => "Ford"
        }
      end
    end
  end
end
