# frozen_string_literal: true

module Fixtures
  # Canonical STI fixture (#6 in the canonical snapshot corpus). Pins
  # the classifier's two access-form verdicts in a single
  # Generated Class — both branches of the rule visible in one snapshot:
  #
  # - +vin+ — column-backed on +Car+ with AR's own auto-generated
  #   reader (inherited from the +Vehicle+ STI base). Verdict:
  #   +:column+. Emits +record._read_attribute("vin")+.
  # - +make+ — column on the table, but +Car+ overrides the reader
  #   (+def make; super.titleize; end+). A user override is honored,
  #   never bypassed. Verdict: +:method+. Emits +record.make+ so the
  #   override runs on every instance.
  #
  # The +sanity_record+ is a +Car+ so the snapshot test
  # (+spec/generators/snapshot_spec.rb+'s tier-3 cell) exercises the
  # override on the +make+ Attribute.
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

    # @return [Car] an unsaved +Car+ with deterministic +vin+ /
    #   +make+ attribute values; the +Car+ choice (over +Vehicle+)
    #   exercises the override on +make+ at the snapshot tier
    def self.sanity_record
      Car.new(id: 1, vin: "ABC123", make: "FORD")
    end

    # @param mode [Symbol] +:json+ or +:hash+
    # @return [String, Hash] the byte-exact expected output of
    #   +serialize_one(sanity_record)+ for +mode+
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
