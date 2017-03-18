require "spec_helper"

RSpec.describe Panko::Serializer do
  Foo = Struct.new(:name, :address, :data)

  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  context "attributes" do
    it "instance variables" do
      serializer = FooSerializer.new
      foo = Foo.new(Faker::Lorem.word, Faker::Lorem.word)

      output = serializer.serialize foo

      expect(output).to eq({
        "name" => foo.name,
        "address" => foo.address
      })
    end

    it "method attributes" do
      class FooWithMethodsSerializer < Panko::Serializer
        attributes :name, :address, :something

        def something
          "#{object.name} #{object.address}"
        end
      end

      serializer = FooWithMethodsSerializer.new

      foo = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      output = serializer.serialize foo

      expect(output).to eq({
        "name" => foo.name,
        "address" => foo.address,
        "something" => "#{foo.name} #{foo.address}"
      })
    end
  end

  context "has_one" do
    it "serializes using the given serializer" do
      FooHolder = Struct.new(:name, :foo)

      class FooHolderSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: FooSerializer
      end

      serializer = FooHolderSerializer.new

      foo = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo_holder = FooHolder.new(Faker::Lorem.word, foo)

      output = serializer.serialize foo_holder

      expect(output).to eq({
        "name" => foo_holder.name,
        "foo" => {
          "name" => foo.name,
          "address" => foo.address,
        }
      })
    end
  end

  context "has_many" do
    it "serializes using the given serializer" do
      FoosHolder = Struct.new(:name, :foos)

      class FoosHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      serializer = FoosHolderSerializer.new

      foo1 = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo2 = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo_holder = FoosHolder.new(Faker::Lorem.word, [foo1, foo2])

      output = serializer.serialize foo_holder

      expect(output).to eq({
        "name" => foo_holder.name,
        "foos" => [
          {
            "name" => foo1.name,
            "address" => foo1.address,
          },
          {
            "name" => foo2.name,
            "address" => foo2.address,
          }
        ]
      })
    end
  end
  # subject -
  #   nil subject
end
