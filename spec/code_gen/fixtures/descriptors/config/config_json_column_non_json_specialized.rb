# frozen_string_literal: true

module Fixtures
  module Config
    # Regression fixture (#61) pinning the non-JSON-typed fallthrough for
    # the S12.5 JSON-column emit knob. +PlainNote+'s +metadata+ column is
    # +t.string+; compiled under +Config#json_column_emit: :wire_format+,
    # the per-Attribute emit stays on today's
    # +push_value(record._read_attribute("metadata"))+ shape because
    # {Generators::RecordAccess::Specialized.json_column_attribute?}
    # rejects a non-+Type::Json+ column — the knob widens the emit only
    # for columns that are provably JSON on the Model.
    #
    # Together with the Generic-path sibling fixture
    # ({ConfigJsonColumnGenericFallthrough}), this snapshot enforces that
    # the JSON-column fast-path emit is Specialized-only and
    # JSON-typed-only — the design contract from
    # +docs/research/json_column_emit_plan.md § 11+. The snapshot delta vs
    # {ConfigJsonColumnWireFormat} is the absence of
    # +read_attribute_before_type_cast+ / +Oj.sc_parse+ / +push_json+ /
    # +Panko::CodeGen::JSON_NOOP_PARSER+ tokens in the body of
    # +_write_one+.
    #
    # +sanity_record+'s +metadata+ holds a JSON-looking String on purpose:
    # the standard emit writes it as a quoted (escaped) JSON string, while
    # a wire-format emit would splice it raw — so the expected output
    # visibly pins which path ran.
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
