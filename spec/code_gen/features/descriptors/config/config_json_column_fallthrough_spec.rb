# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"
require "config/config_json_column_generic_fallthrough"
require "config/config_json_column_non_uniform_specialized"

# Source-token assertion spec for the two regression fixtures filed under
# #61. Pins intent (the JSON-column fast-path emit must not fire), not
# just bytes — even when the snapshot diff for an unrelated emitter
# change happens to keep the +push_value+ shape, the +push_json+ /
# +Oj.sc_parse+ / +SerializersCodeGen::JSON_NOOP_PARSER+ tokens must
# stay absent. The snapshot tier in +spec/generators/snapshot_spec.rb+
# pins exact bytes; this file pins the negative tokens.
#
# Fallthrough paths covered:
#
# - Generic record-access path. The emitter at
#   +lib/serializers_code_gen/generators/record_access/generic.rb+ has no
#   +json_column_attribute?+ branch — every Attribute routes through
#   +FieldEmitters::Attribute.emit_json+. The +Config#json_column_emit:
#   :wire_format+ knob is silently ignored on +Models: nil+ Descriptors.
# - Non-uniform-Specialized path. With +Models: [PlainPost, PlainNote]+
#   the +ar_classes.all? { ... json_typed?(klass, source) }+ guard in
#   {SerializersCodeGen::Generators::RecordAccess::Specialized.json_column_attribute?}
#   (+lib/serializers_code_gen/generators/record_access/specialized.rb+
#   +json_column_attribute?+) returns +false+ because +PlainNote+'s
#   +metadata+ resolves to +Type::String+, not +Type::Json+. The
#   per-Attribute emit downgrades to today's +push_value+ shape.
RSpec.describe "JSON-column emit fallthrough — source token regression" do
  describe "Generic-path Descriptor (Models: nil)" do
    let(:fixture) { Fixtures::Config::ConfigJsonColumnGenericFallthrough }

    it "emits push_value (not push_json) even with json_column_emit: :wire_format" do
      source = SerializersCodeGen::Generator.new.emit(
        fixture::DESCRIPTOR,
        output: :json,
        config: fixture::CONFIG
      )

      expect(source).to include('writer.push_value(record["metadata"])')
      expect(source).to include("writer.push_value(record.metadata)")
      expect(source).not_to include("push_json")
      expect(source).not_to include("Oj.sc_parse")
      expect(source).not_to include("JSON_NOOP_PARSER")
      expect(source).not_to include("read_attribute_before_type_cast")
    end
  end

  describe "non-uniform-Specialized Descriptor (Models with mixed t.json + t.string :metadata)" do
    let(:fixture) { Fixtures::Config::ConfigJsonColumnNonUniformSpecialized }

    it "emits push_value (not push_json) because ar_classes.all? rejects" do
      source = SerializersCodeGen::Generator.new.emit(
        fixture::DESCRIPTOR,
        output: :json,
        config: fixture::CONFIG
      )

      expect(source).to include('writer.push_value(record._read_attribute("metadata"))')
      expect(source).not_to include("push_json")
      expect(source).not_to include("Oj.sc_parse")
      expect(source).not_to include("JSON_NOOP_PARSER")
      expect(source).not_to include("read_attribute_before_type_cast")
    end
  end
end
