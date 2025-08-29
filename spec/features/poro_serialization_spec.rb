# frozen_string_literal: true

require "spec_helper"

describe "PORO Serialization" do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  it "serializes plain objects" do
    class PlainFoo
      attr_accessor :name, :address

      def initialize(name, address)
        @name = name
        @address = address
      end
    end

    foo = PlainFoo.new(Faker::Lorem.word, Faker::Lorem.word)

    expect(foo).to serialized_as(FooSerializer,
      "name" => foo.name,
      "address" => foo.address)
  end
end
