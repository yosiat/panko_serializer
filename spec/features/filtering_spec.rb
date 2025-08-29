# frozen_string_literal: true

require "spec_helper"
require "active_record/connection_adapters/postgresql_adapter"

describe "Filtering Serialization" do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  context "basic filtering" do
    it "supports only filter" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(-> { FooSerializer.new(only: [:name]) }, "name" => foo.name)
    end

    it "supports except filter" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(-> { FooSerializer.new(except: [:name]) }, "address" => foo.address)
    end
  end

  context "association filtering" do
    it "filters associations" do
      class FoosHolderForFilterTestSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      serializer_factory = -> { FoosHolderForFilterTestSerializer.new(only: [:foos]) }

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(serializer_factory, "foos" => [
        {
          "name" => foo1.name,
          "address" => foo1.address
        },
        {
          "name" => foo2.name,
          "address" => foo2.address
        }
      ])
    end

    it 'supports nested "only" filter' do
      class FoosHolderSerializer < Panko::Serializer
        attributes :name
        has_many :foos, serializer: FooSerializer
      end

      serializer_factory = -> { FoosHolderSerializer.new(only: {foos: [:address]}) }

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(serializer_factory, "name" => foos_holder.name,
        "foos" => [
          {
            "address" => foo1.address
          },
          {
            "address" => foo2.address
          }
        ])
    end
  end

  context "filters_for method" do
    it "fetches the filters from the serializer" do
      class FooWithFiltersForSerializer < Panko::Serializer
        attributes :name, :address

        def self.filters_for(_context, _scope)
          {
            only: [:name]
          }
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(FooWithFiltersForSerializer, "name" => foo.name)
    end
  end
end
