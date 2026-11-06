# frozen_string_literal: true

require "spec_helper"

describe "Hash Serialization" do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  it "serializes hash with string keys" do
    foo = {
      "name" => Faker::Lorem.word,
      "address" => Faker::Lorem.word
    }

    expect(foo).to serialized_as(FooSerializer,
      "name" => foo["name"],
      "address" => foo["address"])
  end

  it "serializes HashWithIndifferentAccess with symbol keys" do
    foo = ActiveSupport::HashWithIndifferentAccess.new(
      name: Faker::Lorem.word,
      address: Faker::Lorem.word
    )

    expect(foo).to serialized_as(FooSerializer,
      "name" => foo["name"],
      "address" => foo["address"])
  end

  it "serializes HashWithIndifferentAccess with string keys" do
    foo = ActiveSupport::HashWithIndifferentAccess.new(
      "name" => Faker::Lorem.word,
      "address" => Faker::Lorem.word
    )

    expect(foo).to serialized_as(FooSerializer,
      "name" => foo["name"],
      "address" => foo["address"])
  end

  it "serializes a plain symbol-keyed Hash as null values" do
    # Panko reads Hash records by string key, so a symbol-keyed Hash misses every key.
    foo = {
      name: Faker::Lorem.word,
      address: Faker::Lorem.word
    }

    expect(foo).to serialized_as(FooSerializer,
      "name" => nil,
      "address" => nil)
  end

  context "leaf value normalization" do
    it "stringifies symbol keys in Hash values like the C-ext ObjectWriter" do
      class SymbolHashMethodSerializer < Panko::Serializer
        attributes :data

        def data
          {api_key: "secret", nested: {customer_id: 1}}
        end
      end

      expect({}).to serialized_as(SymbolHashMethodSerializer,
        "data" => {"api_key" => "secret", "nested" => {"customer_id" => 1}})
    end

    it "normalizes objects through their as_json like the C-ext ObjectWriter" do
      class AsJsonValue
        def initialize(id)
          @id = id
        end

        def as_json(*)
          {"id" => @id}
        end
      end

      class AsJsonMethodSerializer < Panko::Serializer
        attributes :value

        def value
          AsJsonValue.new(7)
        end
      end

      expect(AsJsonMethodSerializer.new.serialize({})).to eq("value" => {"id" => 7})
    end
  end
end
