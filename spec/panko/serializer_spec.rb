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

    it "plain object" do
      class PlainFoo
        attr_accessor :name, :address

        def initialize(name, address)
          @name = name
          @address = address
        end
      end

      serializer = FooSerializer.new
      foo = PlainFoo.new(Faker::Lorem.word, Faker::Lorem.word)

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

        def another_method
          raise "I shouldn't get called"
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

    it "supports active record alias attributes" do
      class FooWithAliasesModel < ActiveRecord::Base
        self.table_name = 'foos'
        alias_attribute :full_name, :name
      end

      class FooWithArAliasesSerializer < Panko::Serializer
        attributes :full_name, :address
      end

      foo = FooWithAliasesModel.create(full_name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      serializer = FooWithArAliasesSerializer.new
      output = serializer.serialize foo

      expect(output).to eq("full_name" => foo.name,
                           "address" => foo.address)
    end

    it "allows to alias attributes" do
      class FooWithAliasesSerializer < Panko::Serializer
        attributes :address

        aliases name: :full_name
      end

      serializer = FooWithAliasesSerializer.new

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      output = serializer.serialize foo

      expect(output).to eq("full_name" => foo.name,
                           "address" => foo.address)
    end

    it "serializes null values" do
      serializer = FooSerializer.new

      output = serializer.serialize Foo.create

      expect(output).to eq("name" => nil, "address" => nil)
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
    it "plain object" do
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

      serializer = PlainFooHolderHasOneSerializer.new

      foo = PlainFoo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo_holder = PlainFooHolder.new(Faker::Lorem.word, foo)

      output = serializer.serialize foo_holder

      expect(output).to eq("name" => foo_holder.name,
                           "foo" => {
                             "name" => foo.name,
                             "address" => foo.address
                           })
    end

    it "serializes using the :serializer option" do
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

    it "infers the serializer name by name of the realtionship" do
      class FooHolderHasOneSerializer < Panko::Serializer
        attributes :name

        has_one :foo
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

    it "raises if it can't find the serializer" do
      expect {
        class NotFoundHasOneSerializer < Panko::Serializer
          attributes :name

          has_one :not_existing_serializer
        end
      }.to raise_error("Can't find serializer for NotFoundHasOneSerializer.not_existing_serializer has_one relationship.")
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
    it "serializes using the :serializer option" do
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

    it "infers the serializer name by name of the realtionship" do
      class FoosHasManyHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos
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

    it "raises if it can't find the serializer" do
      expect {
        class NotFoundHasManySerializer < Panko::Serializer
          attributes :name

          has_many :not_existing_serializers
        end
      }.to raise_error("Can't find serializer for NotFoundHasManySerializer.not_existing_serializers has_many relationship.")
    end

    it "serializes using the :each_serializer option" do
      class FoosHasManyHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos, each_serializer: FooSerializer
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

    it "fetches the the filters from the serializer" do
      class FooWithFiltersForSerializer < Panko::Serializer
        attributes :name, :address

        def self.filters_for(context)
          return {
            only: [:name]
          }
        end
      end

      serializer = FooWithFiltersForSerializer.new
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      output = serializer.serialize foo

      expect(output).to eq("name" => foo.name)
    end

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
