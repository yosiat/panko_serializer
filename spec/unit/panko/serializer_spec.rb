# frozen_string_literal: true

require "spec_helper"

describe Panko::Serializer do
  describe "class methods" do
    def descriptor_for(klass)
      Panko::CodeGen::SerializerCache.descriptor_for(klass)
    end

    describe ".inherited" do
      it "builds a descriptor whose parent_class is the serializer" do
        base_class = Class.new(Panko::Serializer)
        child_class = Class.new(base_class)

        expect(descriptor_for(child_class).parent_class).to eq(child_class)
        expect(descriptor_for(child_class)).not_to eq(descriptor_for(base_class))
      end

      it "inherits the parent's attributes" do
        base_class = Class.new(Panko::Serializer) do
          attributes :name
        end

        child_class = Class.new(base_class)

        expect(descriptor_for(child_class).attributes.map(&:name)).to include(:name)
      end

      it "builds an empty descriptor for a serializer with no fields" do
        descriptor = descriptor_for(Class.new(Panko::Serializer))

        expect(descriptor.attributes).to eq([])
        expect(descriptor.method_attributes).to eq([])
        expect(descriptor.associations).to eq([])
      end
    end

    describe ".attributes" do
      it "adds attributes to the descriptor" do
        serializer_class = Class.new(Panko::Serializer) do
          attributes :name, :email
        end

        expect(descriptor_for(serializer_class).attributes.map(&:name)).to include(:name, :email)
      end

      it "ensures uniqueness of attributes" do
        serializer_class = Class.new(Panko::Serializer) do
          attributes :name, :email, :name
        end

        names = descriptor_for(serializer_class).attributes.map(&:name)
        expect(names.count(:name)).to eq(1)
      end
    end

    describe ".aliases" do
      it "maps an aliased attribute to its output name, keyed by source" do
        serializer_class = Class.new(Panko::Serializer) do
          aliases name: :full_name, email: :email_address
        end

        attributes = descriptor_for(serializer_class).attributes
        expect(attributes.find { |a| a.source == :name }.name).to eq(:full_name)
        expect(attributes.find { |a| a.source == :email }.name).to eq(:email_address)
      end
    end

    describe ".method_added" do
      it "moves a matching attribute to a method field when the method is defined" do
        serializer_class = Class.new(Panko::Serializer) do
          attributes :name, :computed_field

          def computed_field
            "computed"
          end
        end

        descriptor = descriptor_for(serializer_class)
        expect(descriptor.attributes.map(&:name)).to include(:name)
        expect(descriptor.attributes.map(&:name)).not_to include(:computed_field)
        expect(descriptor.method_attributes.map(&:name)).to include(:computed_field)
      end

      it "preserves the output name when moving an aliased attribute to a method field" do
        serializer_class = Class.new(Panko::Serializer) do
          aliases computed_field: :computed_alias

          def computed_field
            "computed"
          end
        end

        method_field = descriptor_for(serializer_class).method_attributes.find { |m| m.name == :computed_alias }
        expect(method_field).not_to be_nil
        expect(method_field.body).to eq(:computed_field)
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
  end
end
