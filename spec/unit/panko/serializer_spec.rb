# frozen_string_literal: true

require "spec_helper"

describe Panko::Serializer do
  describe "class methods" do
    describe ".inherited" do
      it "creates a new descriptor for the child class" do
        base_class = Class.new(Panko::Serializer)
        child_class = Class.new(base_class)

        expect(child_class._descriptor).not_to be_nil
        expect(child_class._descriptor).not_to eq(base_class._descriptor)
        expect(child_class._descriptor.type).to eq(child_class)
      end

      it "duplicates parent descriptor when inheriting" do
        base_class = Class.new(Panko::Serializer) do
          attributes :name
        end

        child_class = Class.new(base_class)

        expect(child_class._descriptor.attributes.map(&:name)).to include("name")
        expect(child_class._descriptor).not_to equal(base_class._descriptor)
      end

      it "initializes empty collections for new serializers" do
        serializer_class = Class.new(Panko::Serializer)

        descriptor = serializer_class._descriptor
        expect(descriptor.attributes).to eq([])
        expect(descriptor.aliases).to eq({})
        expect(descriptor.method_fields).to eq([])
        expect(descriptor.has_many_associations).to eq([])
        expect(descriptor.has_one_associations).to eq([])
      end
    end

    describe ".attributes" do
      it "adds attributes to the descriptor" do
        serializer_class = Class.new(Panko::Serializer) do
          attributes :name, :email
        end

        attribute_names = serializer_class._descriptor.attributes.map(&:name)
        expect(attribute_names).to include("name", "email")
      end

      it "ensures uniqueness of attributes" do
        serializer_class = Class.new(Panko::Serializer) do
          attributes :name, :email, :name
        end

        attribute_names = serializer_class._descriptor.attributes.map(&:name)
        expect(attribute_names.count("name")).to eq(1)
      end
    end

    describe ".aliases" do
      it "adds aliased attributes to the descriptor" do
        serializer_class = Class.new(Panko::Serializer) do
          aliases name: :full_name, email: :email_address
        end

        attributes = serializer_class._descriptor.attributes
        name_attr = attributes.find { |attr| attr.name == "name" }
        email_attr = attributes.find { |attr| attr.name == "email" }

        expect(name_attr.alias_name).to eq("full_name")
        expect(email_attr.alias_name).to eq("email_address")
      end
    end

    describe ".method_added" do
      it "moves attribute to method_fields when method is defined" do
        serializer_class = Class.new(Panko::Serializer) do
          attributes :name, :computed_field

          def computed_field
            "computed"
          end
        end

        regular_attributes = serializer_class._descriptor.attributes.map(&:name)
        method_fields = serializer_class._descriptor.method_fields.map(&:name)

        expect(regular_attributes).to include("name")
        expect(regular_attributes).not_to include("computed_field")
        expect(method_fields).to include("computed_field")
      end

      it "preserves alias_name when moving to method_fields" do
        serializer_class = Class.new(Panko::Serializer) do
          aliases computed_field: :computed_alias

          def computed_field
            "computed"
          end
        end

        method_field = serializer_class._descriptor.method_fields.find { |attr| attr.name == "computed_field" }
        expect(method_field.alias_name).to eq("computed_alias")
      end
    end

    describe ".has_one" do
      it "raises error when serializer cannot be found" do
        expect do
          Class.new(Panko::Serializer) do
            has_one :nonexistent_relation
          end
        end.to raise_error(/Can't find serializer/)
      end
    end

    describe ".has_many" do
      it "raises error when serializer cannot be found" do
        expect do
          Class.new(Panko::Serializer) do
            has_many :nonexistent_relations
          end
        end.to raise_error(/Can't find serializer/)
      end
    end
  end

  describe "instance methods" do
    let(:serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name
      end
    end

    describe "#initialize" do
      it "creates serialization context from options" do
        context = {user_id: 123}
        scope = "admin"

        serializer = serializer_class.new(context: context, scope: scope)

        expect(serializer.context).to eq(context)
        expect(serializer.scope).to eq(scope)
      end

      it "builds descriptor with options and context" do
        serializer = serializer_class.new(only: [:name])

        expect(serializer.instance_variable_get(:@descriptor)).not_to be_nil
        expect(serializer.instance_variable_get(:@used)).to eq(false)
      end

      it "skips initialization when _skip_init is true" do
        serializer = serializer_class.new(_skip_init: true)

        expect(serializer.instance_variable_get(:@descriptor)).to be_nil
        expect(serializer.instance_variable_get(:@used)).to be_nil
      end
    end

    describe "#context and #scope" do
      it "returns nil for context and scope when not provided" do
        serializer = serializer_class.new

        expect(serializer.context).to be_nil
        expect(serializer.scope).to be_nil
      end

      it "returns provided context and scope" do
        context = {user_id: 123}
        scope = "admin"

        serializer = serializer_class.new(context: context, scope: scope)

        expect(serializer.context).to eq(context)
        expect(serializer.scope).to eq(scope)
      end
    end

    describe "single-use enforcement" do
      it "raises error on second use" do
        serializer = serializer_class.new
        mock_object = double("object")

        # Mock the Panko.serialize_object call to avoid dependencies
        allow(Panko).to receive(:serialize_object)

        # First call should work
        expect { serializer.serialize(mock_object) }.not_to raise_error

        # Second call should raise error
        expect { serializer.serialize(mock_object) }.to raise_error(ArgumentError, "Panko::Serializer instances are single-use")
      end
    end
  end
end
