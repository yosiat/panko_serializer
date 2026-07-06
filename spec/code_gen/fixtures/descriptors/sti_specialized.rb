# frozen_string_literal: true

module Fixtures
  # Canonical STI fixture (#6 in +docs/testing.md § Canonical snapshot
  # corpus+). Pins the multi-class intersection rule's two access-form
  # verdicts in a single Generated Class — both branches of the rule
  # visible in one snapshot:
  #
  # - +vin+ — uniformly column-backed on +Vehicle+ and +Car+ with no
  #   override on either class. Verdict: +:column+. Emits
  #   +record._read_attribute("vin")+ on both instances.
  # - +make+ — column on the table (so column-backed on both classes)
  #   but +Car+ overrides the reader (+def make; super.titleize; end+).
  #   Per +docs/compilation.md § STI and mixed class sets+, "a subclass
  #   that overrides a column reader downgrades that attribute across
  #   the whole Generated Class." Verdict: +:method+. Emits
  #   +record.make+ on both instances — +Vehicle+ hits AR's
  #   auto-generated reader (returns the raw column value); +Car+ hits
  #   the user override (returns the titleized value).
  #
  # The +sanity_record+ is a +Car+ so the snapshot test
  # (+spec/generators/snapshot_spec.rb+'s tier-3 cell) exercises the
  # override on the +make+ Attribute. The feature spec serializes both
  # +Vehicle+ and +Car+ instances through the same Generated Class to
  # pin both halves of the rule end-to-end.
  module StiSpecialized
    CONFIG = Panko::CodeGen::Config.new
    DESCRIPTOR = Panko::CodeGen::Descriptor.new(
      name: "StiSpecializedSerializer",
      models: [Vehicle, Car],
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
