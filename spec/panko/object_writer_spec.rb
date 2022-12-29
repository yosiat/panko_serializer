# frozen_string_literal: true

require "spec_helper"
require "active_record/connection_adapters/postgresql_adapter"

describe Panko::ObjectWriter do
  let(:writer) { Panko::ObjectWriter.new }

  context "push_object" do
    it "property" do
      writer.push_object
      writer.push_value "yosi", "name"
      writer.pop

      expect(writer.output).to eql("name" => "yosi")
    end

    it "property with separate key value instructions" do
      writer.push_object
      writer.push_key "name"
      writer.push_value "yosi"
      writer.pop

      expect(writer.output).to eql("name" => "yosi")
    end

    it "supports nested objects" do
      writer.push_object
      writer.push_value "yosi", "name"

      writer.push_object("nested")
      writer.push_value "key1", "value"
      writer.pop

      writer.pop

      expect(writer.output).to eql(
        "name" => "yosi",
        "nested" => {
          "value" => "key1"
        }
      )
    end

    it "supports nested arrays" do
      writer.push_object
      writer.push_value "yosi", "name"

      writer.push_object("nested")
      writer.push_value "key1", "value"
      writer.pop

      writer.push_array "values"
      writer.push_object
      writer.push_value "item", "key"
      writer.pop
      writer.pop

      writer.pop

      expect(writer.output).to eql(
        "name" => "yosi",
        "nested" => {
          "value" => "key1"
        },
        "values" => [
          {"key" => "item"}
        ]
      )
    end
  end

  it "supports arrays" do
    writer.push_array

    writer.push_object
    writer.push_value "key1", "value"
    writer.pop

    writer.push_object
    writer.push_value "key2", "value2"
    writer.pop

    writer.pop

    expect(writer.output).to eql([
      {
        "value" => "key1"
      },
      {
        "value2" => "key2"
      }
    ])
  end
end
