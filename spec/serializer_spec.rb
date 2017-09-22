# frozen_string_literal: true

require "spec_helper"
require "active_record/connection_adapters/postgresql_adapter"

describe Panko::Serializer do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  context "instantiation types" do
    it "from database" do
      serializer = FooSerializer.new
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      output = serializer.serialize foo

      expect(output).to eq("name" => foo.name,
                           "address" => foo.address)
    end

    it "from memory" do
      serializer = FooSerializer.new
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      output = serializer.serialize foo

      expect(output).to eq("name" => foo.name,
                           "address" => foo.address)
    end
  end

  context "attributes" do
    it "instance variables" do
      serializer = FooSerializer.new
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      output = serializer.serialize foo

      expect(output).to eq("name" => foo.name,
                           "address" => foo.address)
    end

    it "method attributes" do
      class FooWithMethodsSerializer < Panko::Serializer
        attributes :name, :address, :something

        def something
          "#{object.name} #{object.address}"
        end
      end

      serializer = FooWithMethodsSerializer.new

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      output = serializer.serialize foo

      expect(output).to eq("name" => foo.name,
                           "address" => foo.address,
                           "something" => "#{foo.name} #{foo.address}")
    end

    it "serializes time correctly" do
      ObjectWithTime = Struct.new(:created_at)
      class ObjectWithTimeSerializer < Panko::Serializer
        attributes :created_at
      end

      obj = Foo.create.reload

      output = ObjectWithTimeSerializer.new.serialize obj

      expect(output).to eq("created_at" => obj.created_at.xmlschema)
    end

    it "honors additional types" do
      class FooValueSerializer < Panko::Serializer
        attributes :value
      end

      foo = Foo.instantiate({ "value" => "[1,2,3]" },
                            { "value" => ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Json.new })

      output = FooValueSerializer.new.serialize foo

      expect(output).to eq("value" => [1, 2, 3])
    end
  end

  context "context" do
    it "passes context to attribute methods" do
      class FooWithContextSerializer < Panko::Serializer
        attributes :name, :context_value

        def context_value
          context[:value]
        end
      end

      context = { value: Faker::Lorem.word }
      serializer = FooWithContextSerializer.new(context: context)
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      output = serializer.serialize foo

      expect(output).to eq("name" => foo.name,
                           "context_value" => context[:value])
    end
  end

  context "filter" do
    it "only" do
      serializer = FooSerializer.new(only: [:name])
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      output = serializer.serialize foo

      expect(output).to eq("name" => foo.name)
    end

    it "except" do
      serializer = FooSerializer.new(except: [:name])
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      output = serializer.serialize foo

      expect(output).to eq("address" => foo.address)
    end
  end

  context "has_one" do
    it "serializes using the given serializer" do
      class FooHolderHasOneSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: FooSerializer
      end

      serializer = FooHolderHasOneSerializer.new

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      output = serializer.serialize foo_holder

      expect(output).to eq("name" => foo_holder.name,
                           "foo" => {
                             "name" => foo.name,
                             "address" => foo.address
                           })
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

      serializer = FooHolderHasOneVirtualSerializer.new

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      output = serializer.serialize foo_holder

      expect(output).to eq("name" => foo_holder.name,
                           "foo" => {
                              "virtual" => "Hello #{foo.name}"
                          })
    end

    it "handles nil" do
      class FooHolderHasOneSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: FooSerializer
      end

      serializer = FooHolderHasOneSerializer.new

      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: nil).reload

      output = serializer.serialize foo_holder

      expect(output).to eq("name" => foo_holder.name,
                           "foo" => nil)
    end
  end

  context "has_many" do
    it "serializes using the given serializer" do
      class FoosHasManyHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      serializer = FoosHasManyHolderSerializer.new

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      output = serializer.serialize foos_holder

      expect(output).to eq("name" => foos_holder.name,
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

      serializer = FoosHolderWithOnlySerializer.new

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      output = serializer.serialize foos_holder

      expect(output).to eq("name" => foos_holder.name,
                           "foos" => [
                             {
                               "address" => foo1.address
                             },
                             {
                               "address" => foo2.address
                             }
                           ])
    end

    it "filters associations" do
      class FoosHolderForFilterTestSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      serializer = FoosHolderForFilterTestSerializer.new only: [:foos]

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      output = serializer.serialize foos_holder

      expect(output).to eq("foos" => [
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
  end

  context "filters" do
    it 'support nested "only" filter' do
      class FoosHolderSerializer < Panko::Serializer
        attributes :name
        has_many :foos, serializer: FooSerializer
      end

      serializer = FoosHolderSerializer.new only: { foos: [:address] }

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      output = serializer.serialize foos_holder

      expect(output).to eq("name" => foos_holder.name,
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
