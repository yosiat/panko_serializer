# frozen_string_literal: true

require "spec_helper"

describe Panko::SerializationDescriptor do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  context "attributes" do
    it "simple fields" do
      descriptor = Panko::SerializationDescriptor.build(FooSerializer)

      expect(descriptor).not_to be_nil
      expect(descriptor.attributes).to eq([
                                            Panko::Attribute.create(:name),
                                            Panko::Attribute.create(:address)
                                          ])
    end

    it "method attributes" do
      class SerializerWithMethodsSerializer < Panko::Serializer
        attributes :name, :address, :something

        def something
          "#{object.name} #{object.address}"
        end
      end

      descriptor = Panko::SerializationDescriptor.build(SerializerWithMethodsSerializer)

      expect(descriptor).not_to be_nil
      expect(descriptor.attributes).to eq([
                                            Panko::Attribute.create(:name),
                                            Panko::Attribute.create(:address)
                                          ])
      expect(descriptor.method_fields).to eq([:something])
    end

    it "creates serializer if we have method field" do
      class VirtualSerialier < Panko::Serializer
        attributes :virtual

        def virtual
          "Hello #{object.name}"
        end
      end

      descriptor = Panko::SerializationDescriptor.build(VirtualSerialier)
      serializer = descriptor.build_serializer

      expect(serializer).not_to be_nil
      expect(serializer).to be_a(Panko::Serializer)
    end

    it "aliases" do
      class AttribteAliasesSerializer < Panko::Serializer
        aliases name: :full_name
      end

      descriptor = Panko::SerializationDescriptor.build(AttribteAliasesSerializer)

      expect(descriptor).not_to be_nil
      expect(descriptor.attributes).to eq([
                                            Panko::Attribute.create(:name, alias_name: :full_name)
                                          ])
    end

    it "allows multiple filters in other runs" do
      class MultipleFiltersTestSerializer < Panko::Serializer
        attributes :name, :address
        has_many :foos, each_serializer: FooSerializer
      end

      descriptor = Panko::SerializationDescriptor.build(MultipleFiltersTestSerializer, only: {
                                                          instance: [:foos],
                                                          foos: [:name]
                                                        })

      expect(descriptor.has_many_associations.first.descriptor.attributes).to eq([
                                                                                   Panko::Attribute.create(:name)
                                                                                 ])

      descriptor = Panko::SerializationDescriptor.build(MultipleFiltersTestSerializer)

      expect(descriptor.has_many_associations.first.descriptor.attributes).to eq([
                                                                                   Panko::Attribute.create(:name),
                                                                                   Panko::Attribute.create(:address)
                                                                                 ])
    end
  end

  context "associations" do
    it "has_one: build_descriptor" do
      class BuilderTest_FooHolderHasOneSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: FooSerializer
      end

      descriptor = Panko::SerializationDescriptor.build(BuilderTest_FooHolderHasOneSerializer)

      expect(descriptor).not_to be_nil
      expect(descriptor.attributes).to eq([Panko::Attribute.create(:name)])
      expect(descriptor.method_fields).to be_empty

      expect(descriptor.has_one_associations.count).to eq(1)

      foo_association = descriptor.has_one_associations.first
      expect(foo_association.name_sym).to eq(:foo)

      foo_descriptor = Panko::SerializationDescriptor.build(FooSerializer, {})
      expect(foo_association.descriptor.attributes).to eq(foo_descriptor.attributes)
      expect(foo_association.descriptor.method_fields).to eq(foo_descriptor.method_fields)
    end

    it "has_many: builds descriptor" do
      class BuilderTest_FoosHasManyHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      descriptor = Panko::SerializationDescriptor.build(BuilderTest_FoosHasManyHolderSerializer)

      expect(descriptor).not_to be_nil
      expect(descriptor.attributes).to eq([Panko::Attribute.create(:name)])
      expect(descriptor.method_fields).to be_empty
      expect(descriptor.has_one_associations).to be_empty

      expect(descriptor.has_many_associations.count).to eq(1)

      foo_association = descriptor.has_many_associations.first
      expect(foo_association.name_sym).to eq(:foos)

      foo_descriptor = Panko::SerializationDescriptor.build(FooSerializer, {})
      expect(foo_association.descriptor.attributes).to eq(foo_descriptor.attributes)
      expect(foo_association.descriptor.method_fields).to eq(foo_descriptor.method_fields)
    end
  end

  context "filter" do
    it "only" do
      descriptor = Panko::SerializationDescriptor.build(FooSerializer, only: [:name])

      expect(descriptor).not_to be_nil
      expect(descriptor.attributes).to eq([Panko::Attribute.create(:name)])
      expect(descriptor.method_fields).to be_empty
    end

    it "except" do
      descriptor = Panko::SerializationDescriptor.build(FooSerializer, except: [:name])

      expect(descriptor).not_to be_nil
      expect(descriptor.attributes).to eq([Panko::Attribute.create(:address)])
      expect(descriptor.method_fields).to be_empty
    end

    it "except filters aliases" do
      class ExceptFooWithAliasesSerializer < Panko::Serializer
        aliases name: :full_name, address: :full_address
      end

      descriptor = Panko::SerializationDescriptor.build(ExceptFooWithAliasesSerializer, except: [:full_name])

      expect(descriptor).not_to be_nil
      expect(descriptor.attributes).to eq([Panko::Attribute.create(:address, alias_name: :full_address)])
    end

    it "only filters aliases" do
      class OnlyFooWithAliasesSerializer < Panko::Serializer
        attributes :address
        aliases name: :full_name
      end

      descriptor = Panko::SerializationDescriptor.build(OnlyFooWithAliasesSerializer, only: [:full_name])

      expect(descriptor).not_to be_nil
      expect(descriptor.attributes).to eq([Panko::Attribute.create(:name, alias_name: :full_name)])
    end

    it "only - filters aliases and fields" do
      class OnlyWithFieldsFooWithAliasesSerializer < Panko::Serializer
        attributes :address, :another_field
        aliases name: :full_name
      end

      descriptor = Panko::SerializationDescriptor.build(OnlyWithFieldsFooWithAliasesSerializer, only: %i[full_name address])

      expect(descriptor).not_to be_nil
      expect(descriptor.attributes).to eq([
                                            Panko::Attribute.create(:address),
                                            Panko::Attribute.create(:name, alias_name: :full_name)
                                          ])
    end

    it "filters associations" do
      class FooHasOneSerilizers < Panko::Serializer
        attributes :name

        has_one :foo1, serializer: FooSerializer
        has_one :foo2, serializer: FooSerializer
      end

      descriptor = Panko::SerializationDescriptor.build(FooHasOneSerilizers, only: %i[name foo1])

      expect(descriptor.attributes).to eq([Panko::Attribute.create(:name)])
      expect(descriptor.has_one_associations.count).to eq(1)

      foos_assoc = descriptor.has_one_associations.first
      expect(foos_assoc.name_sym).to eq(:foo1)
      expect(foos_assoc.descriptor.attributes).to eq([Panko::Attribute.create(:name), Panko::Attribute.create(:address)])
    end

    describe "association filters" do
      it "accepts only as option" do
        class AssocFilterTest_FoosHolderSerializer < Panko::Serializer
          attributes :name
          has_many :foos, serializer: FooSerializer
        end

        descriptor = Panko::SerializationDescriptor.build(AssocFilterTest_FoosHolderSerializer, only: { foos: [:address] })

        expect(descriptor.attributes).to eq([Panko::Attribute.create(:name)])
        expect(descriptor.has_many_associations.count).to eq(1)

        foos_assoc = descriptor.has_many_associations.first
        expect(foos_assoc.name_sym).to eq(:foos)
        expect(foos_assoc.descriptor.attributes).to eq([Panko::Attribute.create(:address)])
      end
    end
  end
end
