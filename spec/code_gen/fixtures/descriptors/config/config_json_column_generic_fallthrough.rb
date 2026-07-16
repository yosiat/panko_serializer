# frozen_string_literal: true

module Fixtures
  module Config
    # Regression fixture (#61) pinning the Generic-path fallthrough for the
    # S12.5 JSON-column emit knob. Even when compiled under
    # +Config#json_column_emit: :wire_format+, a Descriptor with +Models+
    # set to +nil+ (Generic record-access path) keeps today's
    # +push_value(record["metadata"])+ / +push_value(record.metadata)+
    # shape. The optimization is Specialized-path-only by design — see the
    # parent S12.5 PRD's "Detection only fires on the Specialized
    # record-access path" clause and
    # +docs/research/json_column_emit_plan.md § 11+'s lock-in.
    #
    # Why the fallthrough fires: the Generic emitter at
    # +lib/panko/code_gen/generators/record_access/generic.rb+ has
    # no +json_column_attribute?+ branch — every Attribute is routed
    # through +FieldEmitters::Attribute.emit_json+ regardless of the
    # backing column type. Pinning this snapshot guards against a future
    # refactor accidentally porting the +emit_json_column+ branch over
    # from {Generators::RecordAccess::Specialized}.
    #
    # The snapshot delta vs +ConfigJsonColumnWireFormat+ is the absence of
    # +read_attribute_before_type_cast+ / +Oj.sc_parse+ / +push_json+ /
    # +Panko::CodeGen::JSON_NOOP_PARSER+ in the body of any helper —
    # the regression contract this fixture pins.
    module ConfigJsonColumnGenericFallthrough
      CONFIG = Panko::CodeGen::Config.new(json_column_emit: :wire_format)
      DESCRIPTOR = Panko::CodeGen::Descriptor.new(
        name: "ConfigJsonColumnGenericFallthroughSerializer",
        model: nil,
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
