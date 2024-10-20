# frozen_string_literal: true

require "spec_helper"

describe Panko::SerializationDescriptor do
  describe "attributes" do
    subject { described_class.build(FooSerializer) }

    class FooSerializer < Panko::Serializer
      attributes :name, :address
    end

    it "returns all attributes" do
      expect(subject.attributes).to match_array([
        Panko::Attribute.create(:name),
        Panko::Attribute.create(:address)
      ])
    end

    it "returns no method fields for FooSerializer" do
      expect(subject.method_fields).to be_empty
    end

    context "with method attributes" do
      class SerializerWithMethodsSerializer < Panko::Serializer
        attributes :name, :address, :something
        def something
          "#{object.name} #{object.address}"
        end
      end
      let(:descriptor) { described_class.build(SerializerWithMethodsSerializer) }

      it "returns attributes" do
        expect(descriptor.attributes).to match_array([
          Panko::Attribute.create(:name),
          Panko::Attribute.create(:address)
        ])
      end

      it "returns method fields" do
        expect(descriptor.method_fields).to contain_exactly(Panko::Attribute.create(:something))
      end
    end

    context "with aliased attributes" do
      class AttribteAliasesSerializer < Panko::Serializer
        aliases name: :full_name
      end
      let(:descriptor) { described_class.build(AttribteAliasesSerializer) }

      it "returns aliased attributes" do
        expect(descriptor.attributes).to contain_exactly(
          Panko::Attribute.create(:name, alias_name: :full_name)
        )
      end
    end
  end

  describe "associations" do
    context "has_one association" do
      class BuilderTestFooHolderHasOneSerializer < Panko::Serializer
        attributes :name
        has_one :foo, serializer: FooSerializer
      end

      class FooSerializer < Panko::Serializer
        attributes :name, :address
      end
      let(:descriptor) { described_class.build(BuilderTestFooHolderHasOneSerializer) }

      it "returns attributes" do
        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:name))
      end

      it "returns no method fields" do
        expect(descriptor.method_fields).to be_empty
      end

      it "returns one has_one association" do
        expect(descriptor.has_one_associations.size).to eq(1)
      end

      it "returns correct has_one association details" do
        foo_association = descriptor.has_one_associations.first
        expect(foo_association.name_sym).to eq(:foo)
        foo_descriptor = described_class.build(FooSerializer, {})
        expect(foo_association.descriptor.attributes).to eq(foo_descriptor.attributes)
        expect(foo_association.descriptor.method_fields).to eq(foo_descriptor.method_fields)
      end
    end

    context "has_many association" do
      class BuilderTestFoosHasManyHolderSerializer < Panko::Serializer
        attributes :name
        has_many :foos, serializer: FooSerializer
      end

      class FooSerializer < Panko::Serializer
        attributes :name, :address
      end
      let(:descriptor) { described_class.build(BuilderTestFoosHasManyHolderSerializer) }

      it "returns attributes" do
        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:name))
      end

      it "returns no method fields" do
        expect(descriptor.method_fields).to be_empty
      end

      it "returns no has_one associations" do
        expect(descriptor.has_one_associations).to be_empty
      end

      it "returns one has_many association" do
        expect(descriptor.has_many_associations.size).to eq(1)
      end

      it "returns correct has_many association details" do
        foo_association = descriptor.has_many_associations.first
        expect(foo_association.name_sym).to eq(:foos)
        foo_descriptor = described_class.build(FooSerializer, {})
        expect(foo_association.descriptor.attributes).to eq(foo_descriptor.attributes)
        expect(foo_association.descriptor.method_fields).to eq(foo_descriptor.method_fields)
      end
    end
  end

  describe "filtering" do
    context "attribute filtering" do
      it "filters attributes with only" do
        class FooSerializer < Panko::Serializer
          attributes :name, :address
        end
        descriptor = described_class.build(FooSerializer, only: [:name])
        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:name))
        expect(descriptor.method_fields).to be_empty
      end

      it "filters attributes with except" do
        class FooSerializer < Panko::Serializer
          attributes :name, :address
        end
        descriptor = described_class.build(FooSerializer, except: [:name])
        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:address))
        expect(descriptor.method_fields).to be_empty
      end

      context "with aliases" do
        class ExceptFooWithAliasesSerializer < Panko::Serializer
          aliases name: :full_name, address: :full_address
        end

        class OnlyFooWithAliasesSerializer < Panko::Serializer
          attributes :address
          aliases name: :full_name
        end

        class OnlyWithFieldsFooWithAliasesSerializer < Panko::Serializer
          attributes :address, :another_field
          aliases name: :full_name
        end

        it "filters aliases with except" do
          descriptor = described_class.build(ExceptFooWithAliasesSerializer, except: [:full_name])
          expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:address, alias_name: :full_address))
        end

        it "filters aliases with only" do
          descriptor = described_class.build(OnlyFooWithAliasesSerializer, only: [:full_name])
          expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:name, alias_name: :full_name))
        end

        it "filters aliases and fields with only" do
          descriptor = described_class.build(OnlyWithFieldsFooWithAliasesSerializer, only: %i[full_name address])
          expect(descriptor.attributes).to match_array([
            Panko::Attribute.create(:address),
            Panko::Attribute.create(:name, alias_name: :full_name)
          ])
        end
      end
    end

    context "association filtering" do
      class FooSerializer < Panko::Serializer
        attributes :name, :address
      end

      it "filters has_one associations with only" do
        class FooHasOneSerilizers < Panko::Serializer
          attributes :name
          has_one :foo1, serializer: FooSerializer
          has_one :foo2, serializer: FooSerializer
        end
        descriptor = described_class.build(FooHasOneSerilizers, only: %i[name foo1])
        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:name))
        expect(descriptor.has_one_associations.size).to eq(1)
        foos_assoc = descriptor.has_one_associations.first
        expect(foos_assoc.name_sym).to eq(:foo1)
        expect(foos_assoc.descriptor.attributes).to match_array([
          Panko::Attribute.create(:name),
          Panko::Attribute.create(:address)
        ])
      end

      it "filters has_many associations with nested only" do
        class AssocFilterTestFoosHolderSerializer < Panko::Serializer
          attributes :name
          has_many :foos, serializer: FooSerializer
        end
        descriptor = described_class.build(AssocFilterTestFoosHolderSerializer, only: {foos: [:address]})
        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:name))
        expect(descriptor.has_many_associations.size).to eq(1)
        foos_assoc = descriptor.has_many_associations.first
        expect(foos_assoc.name_sym).to eq(:foos)
        expect(foos_assoc.descriptor.attributes).to contain_exactly(Panko::Attribute.create(:address))
      end

      context "deep filtering" do
        class DeepFooSerializer < Panko::Serializer
          attributes :name, :address
          has_one :child, serializer: FooSerializer
          has_many :items, serializer: FooSerializer
        end

        it "applies deep only filters" do
          descriptor = described_class.build(DeepFooSerializer, only: {
            instance: [:name, :child, :items],
            child: [:address],
            items: [:name]
          })
          expect(descriptor.attributes.map(&:name).map(&:to_sym)).to contain_exactly(:name)
          expect(descriptor.has_one_associations.first.descriptor.attributes.map(&:name).map(&:to_sym)).to contain_exactly(:address)
          expect(descriptor.has_many_associations.first.descriptor.attributes.map(&:name).map(&:to_sym)).to contain_exactly(:name)
        end

        it "applies deep except filters" do
          descriptor = described_class.build(DeepFooSerializer, except: {
            instance: [:name],
            child: [:address],
            items: [:name]
          })
          expect(descriptor.attributes.map(&:name).map(&:to_sym)).to contain_exactly(:address)
          expect(descriptor.has_one_associations.first.descriptor.attributes.map(&:name).map(&:to_sym)).to contain_exactly(:name)
          expect(descriptor.has_many_associations.first.descriptor.attributes.map(&:name).map(&:to_sym)).to contain_exactly(:address)
        end

        it "handles conflicting filters" do
          descriptor = described_class.build(DeepFooSerializer,
            only: {instance: [:name, :address]},
            except: {instance: [:address]})
          expect(descriptor.attributes.map(&:name).map(&:to_sym)).to contain_exactly(:name)
        end
      end
    end

    context "filter persistence" do
      class FooSerializer < Panko::Serializer
        attributes :name, :address
      end

      class MultipleFiltersTestSerializer < Panko::Serializer
        attributes :name, :address
        has_many :foos, each_serializer: FooSerializer
      end

      it "does not persist filters between runs" do
        descriptor = described_class.build(MultipleFiltersTestSerializer, only: {
          instance: [:foos],
          foos: [:name]
        })
        descriptor2 = described_class.build(MultipleFiltersTestSerializer)
        expect(descriptor.has_many_associations.first.descriptor.attributes).to contain_exactly(Panko::Attribute.create(:name))
        expect(descriptor2.has_many_associations.first.descriptor.attributes).to match_array([
          Panko::Attribute.create(:name),
          Panko::Attribute.create(:address)
        ])
      end
    end

    describe "filter resolution" do
      let(:descriptor) { described_class.new }

      it "handles empty filters" do
        attrs, assocs = descriptor.resolve_filters({}, :only)
        expect(attrs).to be_empty
        expect(assocs).to eq({})
      end

      it "handles array filters" do
        attrs, assocs = descriptor.resolve_filters({only: [:name, :address]}, :only)
        expect(attrs).to match_array([:name, :address])
        expect(assocs).to eq({})
      end

      it "handles hash filters" do
        filters = {
          only: {
            instance: [:name],
            association: [:address]
          }
        }
        attrs, assocs = descriptor.resolve_filters(filters, :only)
        expect(attrs).to match_array([:name])
        expect(assocs).to eq({association: [:address]})
      end
    end
  end

  describe "context handling" do
    it "sets serialization context" do
      class ContextTestSerializer < Panko::Serializer
        attributes :name
        def name
          serialization_context&.custom_name || object.name
        end
      end
      context = OpenStruct.new(custom_name: "CustomName")
      descriptor = described_class.build(ContextTestSerializer, {}, context)
      expect(descriptor.serializer.serialization_context).to eq(context)
    end

    it "propagates context to associations" do
      class ContextTestSerializer < Panko::Serializer
        attributes :name
        def name
          serialization_context&.custom_name || object.name
        end
      end

      class ContextWithAssociationsSerializer < Panko::Serializer
        has_one :foo, serializer: ContextTestSerializer
        has_many :bars, serializer: ContextTestSerializer
      end
      context = OpenStruct.new(custom_name: "CustomName")
      descriptor = described_class.build(ContextWithAssociationsSerializer, {}, context)
      expect(descriptor.has_one_associations.first.descriptor.serializer.serialization_context).to eq(context)
      expect(descriptor.has_many_associations.first.descriptor.serializer.serialization_context).to eq(context)
    end
  end

  describe "duplicate behavior" do
    class FooSerializer < Panko::Serializer
      attributes :name, :address
    end

    class DuplicateTestSerializer < Panko::Serializer
      attributes :name, :address
      def custom_method
        "test"
      end
      has_one :foo, serializer: FooSerializer
      has_many :bars, serializer: FooSerializer
    end

    let(:original) { described_class.build(DuplicateTestSerializer) }
    let(:duplicate) { described_class.duplicate(original) }

    it "creates independent copy of attributes and associations" do
      expect(duplicate.attributes.object_id).not_to eq(original.attributes.object_id)
      expect(duplicate.method_fields.object_id).not_to eq(original.method_fields.object_id)
      expect(duplicate.has_one_associations.first.object_id).not_to eq(original.has_one_associations.first.object_id)
      expect(duplicate.has_many_associations.first.object_id).not_to eq(original.has_many_associations.first.object_id)
    end

    it "maintains same values after duplication" do
      expect(duplicate.attributes).to eq(original.attributes)
      expect(duplicate.method_fields).to eq(original.method_fields)
      expect(duplicate.has_one_associations.map(&:name_sym)).to eq(original.has_one_associations.map(&:name_sym))
      expect(duplicate.has_many_associations.map(&:name_sym)).to eq(original.has_many_associations.map(&:name_sym))
    end
  end
end
