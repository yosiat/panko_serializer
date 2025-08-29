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
end
