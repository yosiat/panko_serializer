# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"
require "shallow_generic"

RSpec.describe "Generated Class for Fixtures::ShallowGeneric" do
  let(:descriptor) { Fixtures::ShallowGeneric::DESCRIPTOR }
  let(:config) { Fixtures::ShallowGeneric::CONFIG }
  let(:generated_class) { SerializersCodeGen.compile(descriptor, output: :json, config: config) }

  describe "#serialize_one" do
    it "serializes a Hash record (string keys) to a JSON String" do
      generated = generated_class.new(descriptor: descriptor)
      record = {"id" => 1, "title" => "hi"}
      expect(generated.serialize_one(record)).to eq('{"id":1,"title":"hi"}')
    end

    it "serializes a PORO Record (Struct) to a JSON String" do
      generated = generated_class.new(descriptor: descriptor)
      record = Struct.new(:id, :title).new(1, "hi")
      expect(generated.serialize_one(record)).to eq('{"id":1,"title":"hi"}')
    end

    it "serializes a Hash record passing context: nil explicitly" do
      generated = generated_class.new(descriptor: descriptor)
      record = {"id" => 1, "title" => "hi"}
      expect(generated.serialize_one(record, context: nil)).to eq('{"id":1,"title":"hi"}')
    end
  end

  describe ".compile" do
    it "returns a fresh, independent class on each call" do
      first = SerializersCodeGen.compile(descriptor, output: :json, config: config)
      second = SerializersCodeGen.compile(descriptor, output: :json, config: config)
      expect(first).not_to equal(second)
    end

    it "returns a class whose instances respond to serialize_one" do
      expect(generated_class.new(descriptor: descriptor)).to respond_to(:serialize_one)
    end
  end

  describe "synthetic backtrace path" do
    it "stamps Method#source_location with (serializers-code-gen: <Name>/<mode>) for instance methods" do
      method = generated_class.instance_method(:_write_one)
      path, line = method.source_location
      expect(path).to eq("(serializers-code-gen: ShallowGenericSerializer/json)")
      expect(line).to be_a(Integer).and(be_positive)
    end
  end

  describe "frozen-string-literal pragma" do
    it "is the first line of the Generator emit output" do
      source = SerializersCodeGen::Generator.new.emit(descriptor, output: :json, config: config)
      expect(source.lines.first.chomp).to eq("# frozen_string_literal: true")
    end
  end
end
