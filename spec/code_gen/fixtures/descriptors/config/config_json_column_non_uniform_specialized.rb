# frozen_string_literal: true

module Fixtures
  module Config
    # Regression fixture (#61) pinning the non-uniform-Specialized
    # fallthrough for the S12.5 JSON-column emit knob. The +Models+ set
    # mixes +PlainPost+ (+t.json :metadata+) with +PlainNote+
    # (+t.string :metadata+); compiled under
    # +Config#json_column_emit: :wire_format+, the per-Attribute emit
    # downgrades to today's +push_value(record._read_attribute("metadata"))+
    # shape because the +ar_classes.all?+ guard in
    # {Generators::RecordAccess::Specialized.json_column_attribute?}
    # (+lib/serializers_code_gen/generators/record_access/specialized.rb+
    # +json_column_attribute?+) rejects the set: +PlainPost+'s +metadata+
    # is +Type::Json+ but +PlainNote+'s +metadata+ is +Type::String+, so
    # the predicate returns +false+ and emit takes the standard
    # +FieldEmitters::Attribute.emit_json+ path.
    #
    # Together with the Generic-path sibling fixture
    # ({ConfigJsonColumnGenericFallthrough}), this snapshot enforces that
    # the JSON-column fast-path emit is Specialized-only and uniform-+Models+-only —
    # the design contract from
    # +docs/research/json_column_emit_plan.md § 11+. The snapshot delta vs
    # {ConfigJsonColumnWireFormat} is the absence of
    # +read_attribute_before_type_cast+ / +Oj.sc_parse+ / +push_json+ /
    # +Panko::CodeGen::JSON_NOOP_PARSER+ tokens in the body of
    # +_write_one+.
    #
    # +sanity_record+ returns a +PlainPost+ instance (one of the two
    # declared classes); the snapshot tier's third assertion exercises
    # the generated +_write_one+ against it. +PlainNote+'s presence in
    # +Models+ is purely a Compile-time signal that drives classification
    # — runtime instances of either class flow through the same monomorphic
    # body.
    module ConfigJsonColumnNonUniformSpecialized
      CONFIG = Panko::CodeGen::Config.new(json_column_emit: :wire_format)
      DESCRIPTOR = Panko::CodeGen::Descriptor.new(
        name: "ConfigJsonColumnNonUniformSpecializedSerializer",
        models: [PlainPost, PlainNote],
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
