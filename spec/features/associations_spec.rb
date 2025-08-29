# frozen_string_literal: true

require "spec_helper"
require "active_record/connection_adapters/postgresql_adapter"

describe "Associations Serialization" do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  context "has_one" do
    it "serializes plain object associations" do
      class PlainFooHolder
        attr_accessor :name, :foo

        def initialize(name, foo)
          @name = name
          @foo = foo
        end
      end

      class PlainFoo
        attr_accessor :name, :address

        def initialize(name, address)
          @name = name
          @address = address
        end
      end

      class PlainFooHolderHasOneSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: FooSerializer
      end

      foo = PlainFoo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo_holder = PlainFooHolder.new(Faker::Lorem.word, foo)

      expect(foo_holder).to serialized_as(PlainFooHolderHasOneSerializer, "name" => foo_holder.name,
        "foo" => {
          "name" => foo.name,
          "address" => foo.address
        })
    end

    it "accepts serializer name as string" do
      class FooHolderHasOneWithStringSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: "FooSerializer"
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(FooHolderHasOneWithStringSerializer, "name" => foo_holder.name,
        "foo" => {
          "name" => foo.name,
          "address" => foo.address
        })
    end

    it "can use the serializer string name when resolving the serializer" do
      class FooHolderHasOnePooWithStringSerializer < Panko::Serializer
        attributes :name

        has_one :goo, serializer: "FooSerializer"
      end

      goo = Goo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, goo: goo).reload

      expect(foo_holder).to serialized_as(
        FooHolderHasOnePooWithStringSerializer,
        "name" => foo_holder.name,
        "goo" => {
          "name" => goo.name,
          "address" => goo.address
        }
      )
    end

    it "accepts name option" do
      class FooHolderHasOneWithNameSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: FooSerializer, name: :my_foo
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(FooHolderHasOneWithNameSerializer, "name" => foo_holder.name,
        "my_foo" => {
          "name" => foo.name,
          "address" => foo.address
        })
    end

    it "serializes using the :serializer option" do
      class FooHolderHasOneSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: FooSerializer
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(FooHolderHasOneSerializer, "name" => foo_holder.name,
        "foo" => {
          "name" => foo.name,
          "address" => foo.address
        })
    end

    it "infers the serializer name by name of the relationship" do
      class FooHolderHasOneSerializer < Panko::Serializer
        attributes :name

        has_one :foo
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(FooHolderHasOneSerializer, "name" => foo_holder.name,
        "foo" => {
          "name" => foo.name,
          "address" => foo.address
        })
    end

    it "raises if it can't find the serializer" do
      expect do
        class NotFoundHasOneSerializer < Panko::Serializer
          attributes :name

          has_one :not_existing_serializer
        end
      end.to raise_error("Can't find serializer for NotFoundHasOneSerializer.not_existing_serializer has_one relationship.")
    end

    it "allows virtual method in has one serializer" do
      class VirtualSerialier < Panko::Serializer
        attributes :virtual

        def virtual
          "Hello #{object.name}"
        end
      end

      class FooHolderHasOneVirtualSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: VirtualSerialier
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(FooHolderHasOneVirtualSerializer, "name" => foo_holder.name,
        "foo" => {
          "virtual" => "Hello #{foo.name}"
        })
    end

    it "handles nil" do
      class FooHolderHasOneSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: FooSerializer
      end

      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: nil).reload

      expect(foo_holder).to serialized_as(FooHolderHasOneSerializer, "name" => foo_holder.name,
        "foo" => nil)
    end
  end

  context "has_many" do
    it "serializes using the :serializer option" do
      class FoosHasManyHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(FoosHasManyHolderSerializer, "name" => foos_holder.name,
        "foos" => [
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

    it "accepts serializer name as string" do
      class FoosHasManyHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: "FooSerializer"
      end

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(FoosHasManyHolderSerializer, "name" => foos_holder.name,
        "foos" => [
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

    it "uses the serializer string name when resolving the serializer" do
      class FoosHasManyPoosHolderSerializer < Panko::Serializer
        attributes :name

        has_many :goos, serializer: "FooSerializer"
      end

      goo1 = Goo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      goo2 = Goo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, goos: [goo1, goo2]).reload

      expect(foos_holder).to serialized_as(
        FoosHasManyPoosHolderSerializer,
        "name" => foos_holder.name,
        "goos" => [
          {
            "name" => goo1.name,
            "address" => goo1.address
          },
          {
            "name" => goo2.name,
            "address" => goo2.address
          }
        ]
      )
    end

    it "supports :name" do
      class FoosHasManyHolderWithNameSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer, name: :my_foos
      end

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(FoosHasManyHolderWithNameSerializer, "name" => foos_holder.name,
        "my_foos" => [
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

    it "infers the serializer name by name of the relationship" do
      class FoosHasManyHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos
      end

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(FoosHasManyHolderSerializer, "name" => foos_holder.name,
        "foos" => [
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

    it "raises if it can't find the serializer" do
      expect do
        class NotFoundHasManySerializer < Panko::Serializer
          attributes :name

          has_many :not_existing_serializers
        end
      end.to raise_error("Can't find serializer for NotFoundHasManySerializer.not_existing_serializers has_many relationship.")
    end

    it "serializes using the :each_serializer option" do
      class FoosHasManyHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos, each_serializer: FooSerializer
      end

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(FoosHasManyHolderSerializer, "name" => foos_holder.name,
        "foos" => [
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

    it "accepts only as option" do
      class FoosHolderWithOnlySerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer, only: [:address]
      end

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(FoosHolderWithOnlySerializer, "name" => foos_holder.name,
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
end
