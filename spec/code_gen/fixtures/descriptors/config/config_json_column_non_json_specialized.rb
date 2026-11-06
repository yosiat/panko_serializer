# frozen_string_literal: true

module Fixtures
  module Config
    # Under +:wire_format+, a string column (+PlainNote#metadata+) keeps +push_value+.
    # The JSON-looking String would be written raw by the wire-format emit, so the output shows which path ran.
    module ConfigJsonColumnNonJsonSpecialized
      CONFIG = Panko::CodeGen::Config.new(json_column_emit: :wire_format)
      DESCRIPTOR = Panko::CodeGen::Descriptor.new(
        name: "ConfigJsonColumnNonJsonSpecializedSerializer",
        model: PlainNote,
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
        PlainNote.new(id: 1, metadata: '{"a":1}')
      end

      def self.expected_output(mode)
        case mode
        when :json then %q({"id":1,"metadata":"{\"a\":1}"})
        end
      end
    end
  end
end
