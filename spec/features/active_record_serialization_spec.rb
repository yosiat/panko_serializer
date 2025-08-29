# frozen_string_literal: true

require "spec_helper"
require "active_record/connection_adapters/postgresql_adapter"

describe "ActiveRecord Serialization" do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  it "serializes objects from database" do
    foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

    expect(foo).to serialized_as(FooSerializer,
      "name" => foo.name,
      "address" => foo.address)
  end

  it "serializes objects from memory" do
    foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

    expect(foo).to serialized_as(FooSerializer,
      "name" => foo.name,
      "address" => foo.address)
  end

  it "preserves changed attributes" do
    foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

    foo.update!(name: "This is a new name")

    expect(foo).to serialized_as(FooSerializer,
      "name" => "This is a new name",
      "address" => foo.address)
  end
end
