# frozen_string_literal: true

module Fixtures
  module Config
    # Config-isolation fixture pinning +Config#json_column_emit: :wire_format+
    # on the Specialized record-access path. The Descriptor uses
    # +PlainPost+ (a +Models: [PlainPost]+ Specialized Descriptor) with a
    # +t.json :metadata+ Attribute so the per-Field emit routes through
    # {Generators::JsonSink}'s wire-format column emit. The snapshot
    # delta vs the +:html_safe+ sibling fixture is the +read_attribute_before_type_cast+ +
    # +Oj.sc_parse+ + +push_json+ pattern in the body of +_write_one+.
    #
    # +sanity_record+ is an unsaved +PlainPost+ instance; with no stored
    # bytes, +read_attribute_before_type_cast+ returns the assigned Hash
    # (not a String), the +is_a?(String)+ guard rejects it, and emit
    # falls through to today's +push_value+ slow path. The expected
    # output therefore matches today's bytes — which is exactly the
    # "the engine degrades cleanly" contract from
    # +docs/research/phase_1_report.md § 8.1+. End-to-end byte-identical
    # behavior on saved records is exercised in
    # +spec/features/json_column_emit_spec.rb+.
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
