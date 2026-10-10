# frozen_string_literal: true

module Fixtures
  module Config
    # Hash mode is left out of MODES: features/concerns/root_key_spec.rb covers it.
    module ConfigRootKeyOn
      CONFIG = Panko::CodeGen::Config.new(supports_root_key: true)
      DESCRIPTOR = Panko::CodeGen::Descriptor.new(
        name: "ConfigRootKeyOnSerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [
          Panko::CodeGen::Attribute.new(name: :id, source: :id)
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
