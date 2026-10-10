# frozen_string_literal: true

require "spec_helper"

describe Panko::ArraySerializer do
  describe "#initialize" do
    it "raises ArgumentError when each_serializer is not provided" do
      expect do
        Panko::ArraySerializer.new([])
      end.to raise_error(ArgumentError, /Please pass valid each_serializer/)
    end

    it "accepts each_serializer option" do
      mock_serializer = Class.new(Panko::Serializer)

      expect do
        Panko::ArraySerializer.new([], each_serializer: mock_serializer)
      end.not_to raise_error
    end

    it "stores subjects" do
      mock_serializer = Class.new(Panko::Serializer)
      subjects = [1, 2, 3]

      array_serializer = Panko::ArraySerializer.new(subjects, each_serializer: mock_serializer)

      expect(array_serializer.subjects).to eq(subjects)
    end
  end

  describe "serialization methods" do
    let(:mock_serializer) { Class.new(Panko::Serializer) }
    let(:subjects) { [double("obj1"), double("obj2")] }
    let(:array_serializer) { Panko::ArraySerializer.new(subjects, each_serializer: mock_serializer) }

    describe "#to_json" do
      it "calls serialize_to_json with stored subjects" do
        expect(array_serializer).to receive(:serialize_to_json).with(subjects)
        array_serializer.to_json
      end
    end
  end
end
