# frozen_string_literal: true

module Fixtures
  module Config
    # Config-isolation fixture #7 from
    # +docs/testing.md § Config-isolation fixtures+ — pins
    # +Config#supports_root_key: true+ emit. The Descriptor is
    # deliberately minimal (1 +Models: nil+ Attribute) so the snapshot
    # delta vs the default-config emit is exactly the +root_key:+ kwarg
    # + wrap branch + +validate_root_key!+ private method.
    #
    # +MODES = [:json]+ per the canonical-corpus row: the wrap behavior
    # surfaces in both modes, but the snapshot pins the JSON emit only
    # — Hash-mode wrap is exercised at the feature tier in
    # +spec/features/concerns/root_key_spec.rb+ which reuses this same
    # Descriptor + Config in both modes (mode-orthogonal).
    module ConfigRootKeyOn
      CONFIG = SerializersCodeGen::Config.new(supports_root_key: true)
      DESCRIPTOR = SerializersCodeGen::Descriptor.new(
        name: "ConfigRootKeyOnSerializer",
        models: nil,
        attributes: [
          SerializersCodeGen::Attribute.new(name: :id, source: :id)
        ],
        method_attributes: [],
        associations: []
      )
      MODES = %i[json]

      def self.sanity_record
        {"id" => 1}
      end

      def self.expected_output(mode)
        case mode
        when :json then '{"id":1}'
        when :hash then {"id" => 1}
        end
      end
    end
  end
end
