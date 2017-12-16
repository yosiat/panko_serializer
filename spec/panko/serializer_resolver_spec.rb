# frozen_string_literal: true

require "spec_helper"

describe Panko::SerializerResolver do
  it "resolves serializer on singular name" do
    class CoolSerializer < Panko::Serializer
    end

    result = Panko::SerializerResolver.resolve("cool")

    expect(result._descriptor).to be_a(Panko::SerializationDescriptor)
    expect(result._descriptor.type).to eq(CoolSerializer)
  end

  it "resolves serializer on plural name" do
    class PersonSerializer < Panko::Serializer
    end

    result = Panko::SerializerResolver.resolve("persons")

    expect(result._descriptor).to be_a(Panko::SerializationDescriptor)
    expect(result._descriptor.type).to eq(PersonSerializer)
  end

  it "resolves serializer on multiple-word name" do
    class MyCoolSerializer < Panko::Serializer
    end

    result = Panko::SerializerResolver.resolve("my_cool")

    expect(result._descriptor).to be_a(Panko::SerializationDescriptor)
    expect(result._descriptor.type).to eq(MyCoolSerializer)
  end

  describe "errors cases" do
    it "returns nil when the serializer name can't be found" do
      expect(Panko::SerializerResolver.resolve("post")).to be_nil
    end

    it "returns nil when the serializer is not Panko::Serializer" do
      class SomeObjectSerializer
      end

      expect(Panko::SerializerResolver.resolve("some_object")).to be_nil
    end
  end

end
