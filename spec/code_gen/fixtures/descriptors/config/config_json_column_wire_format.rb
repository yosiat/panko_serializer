# frozen_string_literal: true

module Fixtures
  module Config
    # +sanity_record+ is unsaved, so +read_attribute_before_type_cast+ returns a Hash and the
    # emit takes the +push_value+ fallback; saved records are covered in json_column_emit_spec.rb.
    module ConfigJsonColumnWireFormat
      CONFIG = Panko::CodeGen::Config.new(json_column_emit: :wire_format)
      DESCRIPTOR = Panko::CodeGen::Descriptor.new(
        name: "ConfigJsonColumnWireFormatSerializer",
        model: PlainPost,
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
        PlainPost.new(id: 1, metadata: {"a" => 1, "b" => "x"})
      end

      def self.expected_output(mode)
        case mode
        when :json then '{"id":1,"metadata":{"a":1,"b":"x"}}'
        end
      end
    end
  end
end
