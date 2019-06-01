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

      expect(foo).to serialized_as(serializer,
                                   "name" => foo.name,
                                   "address" => foo.address)
    end

    it "from memory" do
      serializer = FooSerializer.new
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(serializer,
                                   "name" => foo.name,
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

      expect(foo).to serialized_as(serializer,
                                   "name" => foo.name,
                                   "address" => foo.address)
    end
  end

  context "attributes" do
    it "instance variables" do
      serializer = FooSerializer.new
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(serializer,
                                   "name" => foo.name,
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

      expect(foo).to serialized_as(serializer, "name" => foo.name,
                                               "address" => foo.address,
                                               "something" => "#{foo.name} #{foo.address}")
    end

    it "supports serailizer inheritance" do
      class BaseSerializer < Panko::Serializer
        attributes :name
      end

      class ChildSerializer < BaseSerializer
        attributes :address
      end

      serializer = ChildSerializer.new

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(serializer, "name" => foo.name,
                                               "address" => foo.address)
    end

    it "serializes time correctly" do
      class ObjectWithTimeSerializer < Panko::Serializer
        attributes :created_at, :method

        def method
          object.created_at
        end
      end

      obj = Foo.create.reload

      expect(obj).to serialized_as(ObjectWithTimeSerializer.new,
                                   "created_at" => obj.created_at.as_json,
                                   "method" => obj.created_at.as_json)
    end

    it "honors additional types" do
      class FooValueSerializer < Panko::Serializer
        attributes :value
      end

      foo = Foo.instantiate({ "value" => "1" },
                            "value" => ActiveRecord::Type::Integer.new)

      expect(foo).to serialized_as(FooValueSerializer.new, "value" => 1)
    end

    it "supports active record alias attributes" do
      class FooWithAliasesModel < ActiveRecord::Base
        self.table_name = "foos"
        alias_attribute :full_name, :name
      end

      class FooWithArAliasesSerializer < Panko::Serializer
        attributes :full_name, :address
      end

      foo = FooWithAliasesModel.create(full_name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(FooWithArAliasesSerializer.new, "full_name" => foo.name, "address" => foo.address)
    end

    it "allows to alias attributes" do
      class FooWithAliasesSerializer < Panko::Serializer
        attributes :address

        aliases name: :full_name
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(FooWithAliasesSerializer.new, "full_name" => foo.name, "address" => foo.address)
    end

    it "serializes null values" do
      expect(Foo.create).to serialized_as(FooSerializer.new, "name" => nil, "address" => nil)
    end

    it "preserves changed attributes" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      foo.update!(name: "This is a new name")

      expect(foo).to serialized_as(FooSerializer.new,
                                   "name" => "This is a new name",
                                   "address" => foo.address)
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

      expect(foo).to serialized_as(serializer,
                                   "name" => foo.name,
                                   "context_value" => context[:value])
    end
  end

  context "scope" do
    class FooWithScopeSerializer < Panko::Serializer
      attributes :scope_value

      def scope_value
        scope
      end
    end

    class FooHolderWithScopeSerializer < Panko::Serializer
      attributes :scope_value

      has_one :foo, serializer: FooWithScopeSerializer

      def scope_value
        scope
      end
    end

    it "passes scope to attribute methods" do
      scope = 123
      serializer = FooHolderWithScopeSerializer.new(scope: scope)

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(serializer,
                                          "scope_value" => scope,
                                          "foo" => {
                                            "scope_value" => scope
                                          })
    end

    it "default scope is nil" do
      serializer = FooHolderWithScopeSerializer.new

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(serializer, "scope_value" => nil,
                                                      "foo" => {
                                                        "scope_value" => nil
                                                      })
    end
  end

  context "filter" do
    it "only" do
      serializer = FooSerializer.new(only: [:name])
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(serializer, "name" => foo.name)
    end

    it "except" do
      serializer = FooSerializer.new(except: [:name])
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(serializer, "address" => foo.address)
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

      expect(foo_holder).to serialized_as(serializer, "name" => foo_holder.name,
                                                      "foo" => {
                                                        "name" => foo.name,
                                                        "address" => foo.address
                                                      })
    end

    it "accepts name option" do
      class FooHolderHasOneWithNameSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: FooSerializer, name: :my_foo
      end

      serializer = FooHolderHasOneWithNameSerializer.new

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(serializer, "name" => foo_holder.name,
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

      serializer = FooHolderHasOneSerializer.new

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(serializer, "name" => foo_holder.name,
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

      expect(foo_holder).to serialized_as(serializer, "name" => foo_holder.name,
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

      serializer = FooHolderHasOneVirtualSerializer.new

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(serializer, "name" => foo_holder.name,
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

      expect(foo_holder).to serialized_as(serializer, "name" => foo_holder.name,
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

      expect(foos_holder).to serialized_as(serializer, "name" => foos_holder.name,
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

    it "supports :name" do
      class FoosHasManyHolderWithNameSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer, name: :my_foos
      end

      serializer = FoosHasManyHolderWithNameSerializer.new

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(serializer, "name" => foos_holder.name,
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
    it "infers the serializer name by name of the realtionship" do
      class FoosHasManyHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos
      end

      serializer = FoosHasManyHolderSerializer.new

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(serializer, "name" => foos_holder.name,
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

      serializer = FoosHasManyHolderSerializer.new

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(serializer, "name" => foos_holder.name,
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

      expect(foos_holder).to serialized_as(serializer, "name" => foos_holder.name,
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

      expect(foos_holder).to serialized_as(serializer, "foos" => [
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

        def self.filters_for(_context, _scope)
          {
            only: [:name]
          }
        end
      end

      serializer = FooWithFiltersForSerializer.new
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(serializer, "name" => foo.name)
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

      expect(foos_holder).to serialized_as(serializer, "name" => foos_holder.name,
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
