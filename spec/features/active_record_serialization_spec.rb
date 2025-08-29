# frozen_string_literal: true

require "spec_helper"

describe "ActiveRecord Serialization" do
  before do
    Temping.create(:foo) do
      with_columns do |t|
        t.string :name
        t.string :address
      end
    end
  end

  it "serializes objects from database" do
    class FooSerializer < Panko::Serializer
      attributes :name, :address
    end

    foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

    expect(foo).to serialized_as(FooSerializer,
      "name" => foo.name,
      "address" => foo.address)
  end

  it "serializes objects from memory" do
    class FooSerializer < Panko::Serializer
      attributes :name, :address
    end

    foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

    expect(foo).to serialized_as(FooSerializer,
      "name" => foo.name,
      "address" => foo.address)
  end

  it "preserves changed attributes" do
    class FooSerializer < Panko::Serializer
      attributes :name, :address
    end

    foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

    foo.update!(name: "This is a new name")

    expect(foo).to serialized_as(FooSerializer,
      "name" => "This is a new name",
      "address" => foo.address)
  end
end
