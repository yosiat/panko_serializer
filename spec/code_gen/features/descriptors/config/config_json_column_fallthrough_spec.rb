# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "config/config_json_column_generic_fallthrough"
require "config/config_json_column_non_json_specialized"

RSpec.describe "JSON-column emit fallthrough — source token regression" do
  describe "Generic-path Descriptor (Models: nil)" do
    let(:fixture) { Fixtures::Config::ConfigJsonColumnGenericFallthrough }

    it "emits push_value (not push_json) even with json_column_emit: :wire_format" do
      source = Panko::CodeGen::Generator.new.emit(
        fixture::DESCRIPTOR,
        output: :json,
        config: fixture::CONFIG
      )

      expect(source).to include('writer.push_value(record["metadata"], "metadata")')
      expect(source).to include('writer.push_value(record.metadata, "metadata")')
      expect(source).not_to include("push_json")
      expect(source).not_to include("Oj.sc_parse")
      expect(source).not_to include("JSON_NOOP_PARSER")
      expect(source).not_to include("read_attribute_before_type_cast")
    end
  end

  describe "non-uniform-Specialized Descriptor (Models with mixed t.json + t.string :metadata)" do
    let(:fixture) { Fixtures::Config::ConfigJsonColumnNonJsonSpecialized }

    it "emits push_value (not push_json) because ar_classes.all? rejects" do
      source = Panko::CodeGen::Generator.new.emit(
        fixture::DESCRIPTOR,
        output: :json,
        config: fixture::CONFIG
      )

      expect(source).to include('writer.push_value(record._read_attribute("metadata"), "metadata")')
      expect(source).not_to include("push_json")
      expect(source).not_to include("Oj.sc_parse")
      expect(source).not_to include("JSON_NOOP_PARSER")
      expect(source).not_to include("read_attribute_before_type_cast")
    end
  end
end
