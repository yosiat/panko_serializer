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

    it "builds serialization context from options" do
      mock_serializer = Class.new(Panko::Serializer)
      context = {user_id: 123}
      scope = "admin"

      array_serializer = Panko::ArraySerializer.new([],
        each_serializer: mock_serializer,
        context: context,
        scope: scope)

      serialization_context = array_serializer.instance_variable_get(:@serialization_context)
      expect(serialization_context.context).to eq(context)
      expect(serialization_context.scope).to eq(scope)
    end

    it "passes filtering options to descriptor" do
      mock_serializer = Class.new(Panko::Serializer)

      # Mock SerializationDescriptor.build to verify options are passed
      expect(Panko::SerializationDescriptor).to receive(:build).with(
        mock_serializer,
        hash_including(
          only: [:name],
          except: [:email],
          context: {user_id: 123},
          scope: "admin"
        ),
        anything
      )

      Panko::ArraySerializer.new([],
        each_serializer: mock_serializer,
        only: [:name],
        except: [:email],
        context: {user_id: 123},
        scope: "admin")
    end

    it "defaults only and except to empty arrays when not provided" do
      mock_serializer = Class.new(Panko::Serializer)

      expect(Panko::SerializationDescriptor).to receive(:build).with(
        mock_serializer,
        hash_including(
          only: [],
          except: []
        ),
        anything
      )

      Panko::ArraySerializer.new([], each_serializer: mock_serializer)
    end
  end

  describe "option handling" do
    let(:mock_serializer) { Class.new(Panko::Serializer) }

    it "handles only option" do
      array_serializer = Panko::ArraySerializer.new([],
        each_serializer: mock_serializer,
        only: [:name, :email])

      # Verify that the descriptor was built with the only option
      descriptor = array_serializer.instance_variable_get(:@descriptor)
      expect(descriptor).not_to be_nil
    end

    it "handles except option" do
      array_serializer = Panko::ArraySerializer.new([],
        each_serializer: mock_serializer,
        except: [:password, :secret])

      descriptor = array_serializer.instance_variable_get(:@descriptor)
      expect(descriptor).not_to be_nil
    end

    it "handles context option" do
      context = {current_user: "admin"}
      array_serializer = Panko::ArraySerializer.new([],
        each_serializer: mock_serializer,
        context: context)

      serialization_context = array_serializer.instance_variable_get(:@serialization_context)
      expect(serialization_context.context).to eq(context)
    end

    it "handles scope option" do
      scope = "public"
      array_serializer = Panko::ArraySerializer.new([],
        each_serializer: mock_serializer,
        scope: scope)

      serialization_context = array_serializer.instance_variable_get(:@serialization_context)
      expect(serialization_context.scope).to eq(scope)
    end
  end

  describe "serialization methods" do
    let(:mock_serializer) { Class.new(Panko::Serializer) }
    let(:subjects) { [double("obj1"), double("obj2")] }
    let(:array_serializer) { Panko::ArraySerializer.new(subjects, each_serializer: mock_serializer) }

    describe "#serialize" do
      it "calls Panko.serialize_objects with correct parameters" do
        mock_writer = double("writer", output: [])
        allow(Panko::ObjectWriter).to receive(:new).and_return(mock_writer)

        expect(Panko).to receive(:serialize_objects).with(
          subjects,
          mock_writer,
          array_serializer.instance_variable_get(:@descriptor)
        )

        array_serializer.serialize(subjects)
      end
    end

    describe "#to_a" do
      it "calls serialize_with_writer with stored subjects" do
        mock_writer = double("writer", output: [])
        allow(Panko::ObjectWriter).to receive(:new).and_return(mock_writer)

        expect(Panko).to receive(:serialize_objects).with(
          subjects,
          mock_writer,
          anything
        )

        array_serializer.to_a
      end
    end

    describe "#serialize_to_json" do
      it "uses Oj::StringWriter for JSON output" do
        mock_writer = double("writer", to_s: "[]")
        allow(Oj::StringWriter).to receive(:new).with(mode: :rails).and_return(mock_writer)
        allow(Panko).to receive(:serialize_objects)

        result = array_serializer.serialize_to_json(subjects)
        expect(result).to eq("[]")
      end
    end

    describe "#to_json" do
      it "calls serialize_to_json with stored subjects" do
        expect(array_serializer).to receive(:serialize_to_json).with(subjects)
        array_serializer.to_json
      end
    end
  end
end
