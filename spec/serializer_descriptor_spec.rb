# frozen_string_literal: true

require "spec_helper"

describe Panko::SerializationDescriptorBuilder do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  context "attributes" do
    it "simple fields" do
      descriptor = Panko::SerializationDescriptorBuilder.build(FooSerializer)

      expect(descriptor).not_to be_nil
      expect(descriptor.fields).to eq([:name, :address])
    end

    it "method attributes" do
      class SerializerWithMethodsSerializer < Panko::Serializer
        attributes :name, :address, :something

        def something
          "#{object.name} #{object.address}"
        end
      end

      descriptor = Panko::SerializationDescriptorBuilder.build(SerializerWithMethodsSerializer)

      expect(descriptor).not_to be_nil
      expect(descriptor.fields).to eq([:name, :address])
      expect(descriptor.method_fields).to eq([:something])
    end


    it "creates serializer if we have method field" do
      class VirtualSerialier < Panko::Serializer
        attributes :virtual

        def virtual
          "Hello #{object.name}"
        end
      end

      descriptor = Panko::SerializationDescriptorBuilder.build(VirtualSerialier)
      serializer = descriptor.build_serializer

      expect(serializer).not_to be_nil
      expect(serializer).to be_a(Panko::Serializer)
    end
  end

  context "associations" do
    it "has_one: build_descriptor" do
      class FooHolderHasOneSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: FooSerializer
      end

      descriptor = Panko::SerializationDescriptorBuilder.build(FooHolderHasOneSerializer)

      expect(descriptor).not_to be_nil
      expect(descriptor.fields).to eq([:name])
      expect(descriptor.method_fields).to be_empty

      expect(descriptor.has_one_associations.count).to eq(1)

      foo_association = descriptor.has_one_associations.first
      expect(foo_association.first).to eq(:foo)

      foo_descriptor = Panko::SerializationDescriptorBuilder.build(FooSerializer, {})
      expect(foo_association.last.fields).to eq(foo_descriptor.fields)
      expect(foo_association.last.method_fields).to eq(foo_descriptor.method_fields)
    end

    it "has_many: builds descriptor" do
      class FoosHasManyHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      descriptor = Panko::SerializationDescriptorBuilder.build(FoosHasManyHolderSerializer)

      expect(descriptor).not_to be_nil
      expect(descriptor.fields).to eq([:name])
      expect(descriptor.method_fields).to be_empty
      expect(descriptor.has_one_associations).to be_empty

      expect(descriptor.has_many_associations.count).to eq(1)

      foo_association = descriptor.has_many_associations.first
      expect(foo_association.first).to eq(:foos)

      foo_descriptor = Panko::SerializationDescriptorBuilder.build(FooSerializer, {})
      expect(foo_association.last.fields).to eq(foo_descriptor.fields)
      expect(foo_association.last.method_fields).to eq(foo_descriptor.method_fields)
    end
  end

  context "filter" do
    it "only" do
      descriptor = Panko::SerializationDescriptorBuilder.build(FooSerializer, only: [:name])

      expect(descriptor).not_to be_nil
      expect(descriptor.fields).to eq([:name])
      expect(descriptor.method_fields).to be_empty
    end

    it "except" do
      descriptor = Panko::SerializationDescriptorBuilder.build(FooSerializer, except: [:name])

      expect(descriptor).not_to be_nil
      expect(descriptor.fields).to eq([:address])
      expect(descriptor.method_fields).to be_empty
    end

    it "filters associations" do
      class FooHasOneSerilizers < Panko::Serializer
        attributes :name

        has_one :foo1, serializer: FooSerializer
        has_one :foo2, serializer: FooSerializer
      end

      descriptor = Panko::SerializationDescriptorBuilder.build(FooHasOneSerilizers, only: [:name, :foo1])

      expect(descriptor.fields).to eq([:name])
      expect(descriptor.has_one_associations.count).to eq(1)

      foos_assoc = descriptor.has_one_associations.first
      expect(foos_assoc.first).to eq(:foo1)
      expect(foos_assoc.last.fields).to eq([:name, :address])
    end

    describe "association filters" do
      it "accepts only as option" do
        class FoosHolderSerializer < Panko::Serializer
          attributes :name
          has_many :foos, serializer: FooSerializer
        end

        descriptor = Panko::SerializationDescriptorBuilder.build(FoosHolderSerializer, only: { foos: [:address] })

        expect(descriptor.fields).to eq([:name])
        expect(descriptor.has_many_associations.count).to eq(1)

        foos_assoc = descriptor.has_many_associations.first
        expect(foos_assoc.first).to eq(:foos)
        expect(foos_assoc.last.fields).to eq([:address])
      end

    end
  end
end
