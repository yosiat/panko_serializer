# frozen_string_literal: true

module Fixtures
  module Config
    # Pins that +json_column_emit: :wire_format+ changes nothing on the Generic
    # path (+model: nil+): only the Specialized path checks for JSON columns.
    module ConfigJsonColumnGenericFallthrough
      CONFIG = Panko::CodeGen::Config.new(json_column_emit: :wire_format)
      DESCRIPTOR = Panko::CodeGen::Descriptor.new(
        name: "ConfigJsonColumnGenericFallthroughSerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [
          Panko::CodeGen::Attribute.new(name: :id, source: :id),
          Panko::CodeGen::Attribute.new(name: :metadata, source: :metadata)
        ],
        method_attributes: [],
        associations: []
      )
      MODES = %i[json]

      def self.sanity_record
        {"id" => 1, "metadata" => {"a" => 1, "b" => "x"}}
      end

      def self.expected_output(mode)
        case mode
        when :json then '{"id":1,"metadata":{"a":1,"b":"x"}}'
        end
      end
    end
  end
end
