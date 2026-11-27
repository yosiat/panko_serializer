# frozen_string_literal: true

module Fixtures
  module Config
    # The Method Attribute shows that only Attributes get the nil guard.
    module ConfigOmitNilAttributes
      CONFIG = Panko::CodeGen::Config.new(omit_nil_attributes: true)
      DESCRIPTOR = Panko::CodeGen::Descriptor.new(
        name: "ConfigOmitNilAttributesSerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [
          Panko::CodeGen::Attribute.new(name: :id, source: :id),
          Panko::CodeGen::Attribute.new(name: :name, source: :name)
        ],
        method_attributes: [
          Panko::CodeGen::MethodAttribute.new(name: :nickname, body: -> {})
        ],
        associations: []
      )
      MODES = %i[json hash]

      def self.sanity_record
        {"id" => 1, "name" => nil}
      end

      def self.expected_output(mode)
        case mode
        when :json then '{"id":1,"nickname":null}'
        when :hash then {"id" => 1, "nickname" => nil}
        end
      end
    end
  end
end
