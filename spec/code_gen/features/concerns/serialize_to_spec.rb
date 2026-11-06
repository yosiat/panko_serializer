# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

RSpec.describe "serialize_one_to / serialize_many_to - write into a caller's writer" do
  let(:descriptor) do
    Panko::CodeGen::Descriptor.new(
      name: "SerializeToSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :title, source: :title)
      ],
      method_attributes: [],
      associations: []
    )
  end

  let(:generated) { Panko::CodeGen.compile(descriptor, output: :json).new(descriptor: descriptor) }
  let(:records) { [{"id" => 1, "title" => "first"}, {"id" => 2, "title" => "second"}] }
  let(:key) { "items" }
  let(:writer) { Oj::StringWriter.new(mode: :rails) }

  def document
    writer.to_s.chomp
  end

  describe "serialize_many_to" do
    it "writes the same array serialize_many returns, under the key" do
      writer.push_object
      generated.serialize_many_to(writer, records, key)
      writer.pop

      expect(document).to eq(%({"#{key}":#{generated.serialize_many(records)}}))
    end

    it "writes the array as the next element when the key is nil" do
      writer.push_array
      generated.serialize_many_to(writer, records)
      writer.pop

      expect(document).to eq("[#{generated.serialize_many(records)}]")
    end

    it "applies filters" do
      filters = {only: [:id]}
      writer.push_object
      generated.serialize_many_to(writer, records, key, filters: filters)
      writer.pop

      expect(document).to eq(%({"#{key}":#{generated.serialize_many(records, filters: filters)}}))
    end

    it "returns nil" do
      writer.push_array
      expect(generated.serialize_many_to(writer, records)).to be_nil
    end
  end

  describe "serialize_one_to" do
    it "writes the same object serialize_one returns, under the key" do
      writer.push_object
      generated.serialize_one_to(writer, records.first, key)
      writer.pop

      expect(document).to eq(%({"#{key}":#{generated.serialize_one(records.first)}}))
    end

    it "writes the object as the next element when the key is nil" do
      writer.push_array
      records.each { |record| generated.serialize_one_to(writer, record) }
      writer.pop

      expect(document).to eq(generated.serialize_many(records))
    end
  end

  it "is not defined in Hash mode" do
    hash_generated = Panko::CodeGen.compile(descriptor, output: :hash).new(descriptor: descriptor)

    expect(hash_generated).not_to respond_to(:serialize_one_to)
    expect(hash_generated).not_to respond_to(:serialize_many_to)
  end
end
