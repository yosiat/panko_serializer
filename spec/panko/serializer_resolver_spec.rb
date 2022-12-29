# frozen_string_literal: true

require "spec_helper"

describe Panko::SerializerResolver do
  it "resolves serializer on singular name" do
    class CoolSerializer < Panko::Serializer
    end

    result = Panko::SerializerResolver.resolve("cool", Object)

    expect(result._descriptor).to be_a(Panko::SerializationDescriptor)
    expect(result._descriptor.type).to eq(CoolSerializer)
  end

  it "resolves serializer on plural name" do
    class PersonSerializer < Panko::Serializer
    end

    result = Panko::SerializerResolver.resolve("persons", Object)

    expect(result._descriptor).to be_a(Panko::SerializationDescriptor)
    expect(result._descriptor.type).to eq(PersonSerializer)
  end

  it "resolves serializer on multiple-word name" do
    class MyCoolSerializer < Panko::Serializer
    end

    result = Panko::SerializerResolver.resolve("my_cool", Object)

    expect(result._descriptor).to be_a(Panko::SerializationDescriptor)
    expect(result._descriptor.type).to eq(MyCoolSerializer)
  end

  it "resolves serializer in namespace first" do
    class CoolSerializer < Panko::Serializer
    end

    module MyApp
      class CoolSerializer < Panko::Serializer
      end

      class PersonSerializer < Panko::Serializer
      end
    end

    result = Panko::SerializerResolver.resolve("cool", MyApp::PersonSerializer)
    expect(result._descriptor).to be_a(Panko::SerializationDescriptor)
    expect(result._descriptor.type).to eq(MyApp::CoolSerializer)

    result = Panko::SerializerResolver.resolve("cool", Panko)
    expect(result._descriptor).to be_a(Panko::SerializationDescriptor)
    expect(result._descriptor.type).to eq(CoolSerializer)
  end

  describe "errors cases" do
    it "returns nil when the serializer name can't be found" do
      expect(Panko::SerializerResolver.resolve("post", Object)).to be_nil
    end

    it "returns nil when the serializer is not Panko::Serializer" do
      class SomeObjectSerializer
      end

      expect(Panko::SerializerResolver.resolve("some_object", Object)).to be_nil
    end
  end
end
