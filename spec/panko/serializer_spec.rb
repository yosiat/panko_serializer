# frozen_string_literal: true

require "spec_helper"
require "active_record/connection_adapters/postgresql_adapter"

describe Panko::Serializer do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  context "instantiation types" do
    it "from database" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(FooSerializer,
        "name" => foo.name,
        "address" => foo.address)
    end

    it "from memory" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(FooSerializer,
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

      foo = PlainFoo.new(Faker::Lorem.word, Faker::Lorem.word)

      expect(foo).to serialized_as(FooSerializer,
        "name" => foo.name,
        "address" => foo.address)
    end

    it "hash (with string keys)" do
      foo = {
        "name" => Faker::Lorem.word,
        "address" => Faker::Lorem.word
      }

      expect(foo).to serialized_as(FooSerializer,
        "name" => foo["name"],
        "address" => foo["address"])
    end

    it "HashWithIndifferentAccess (with symbol keys)" do
      foo = ActiveSupport::HashWithIndifferentAccess.new(
        name: Faker::Lorem.word,
        address: Faker::Lorem.word
      )

      expect(foo).to serialized_as(FooSerializer,
        "name" => foo["name"],
        "address" => foo["address"])
    end

    it "HashWithIndifferentAccess (with string keys)" do
      foo = ActiveSupport::HashWithIndifferentAccess.new(
        "name" => Faker::Lorem.word,
        "address" => Faker::Lorem.word
      )

      expect(foo).to serialized_as(FooSerializer,
        "name" => foo["name"],
        "address" => foo["address"])
    end
  end

  context "attributes" do
    it "instance variables" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(FooSerializer,
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

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(FooWithMethodsSerializer, "name" => foo.name,
        "address" => foo.address,
        "something" => "#{foo.name} #{foo.address}")
    end

    it "supports serializer inheritance" do
      class BaseSerializer < Panko::Serializer
        attributes :name
      end

      class ChildSerializer < BaseSerializer
        attributes :address
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(ChildSerializer, "name" => foo.name,
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

      expect(obj).to serialized_as(ObjectWithTimeSerializer,
        "created_at" => obj.created_at.as_json,
        "method" => obj.created_at.as_json)
    end

    it "honors additional types" do
      class FooValueSerializer < Panko::Serializer
        attributes :value
      end

      foo = Foo.instantiate({"value" => "1"},
        "value" => ActiveRecord::Type::Integer.new)

      expect(foo).to serialized_as(FooValueSerializer, "value" => 1)
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

      expect(foo).to serialized_as(FooWithArAliasesSerializer, "full_name" => foo.name, "address" => foo.address)
    end

    it "allows to alias attributes" do
      class FooWithAliasesSerializer < Panko::Serializer
        attributes :address

        aliases name: :full_name
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(FooWithAliasesSerializer, "full_name" => foo.name, "address" => foo.address)
    end

    it "serializes null values" do
      expect(Foo.create).to serialized_as(FooSerializer, "name" => nil, "address" => nil)
    end

    it "can skip fields" do
      class FooSkipSerializer < FooSerializer
        def address
          object.address || SKIP
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      expect(foo).to serialized_as(FooSkipSerializer, "name" => foo.name, "address" => foo.address)

      foo = Foo.create(name: Faker::Lorem.word, address: nil).reload
      expect(foo).to serialized_as(FooSkipSerializer, "name" => foo.name)
    end

    it "preserves changed attributes" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      foo.update!(name: "This is a new name")

      expect(foo).to serialized_as(FooSerializer,
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

      context = {value: Faker::Lorem.word}
      serializer_factory = -> { FooWithContextSerializer.new(context: context) }
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(serializer_factory,
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
      serializer_factory = -> { FooHolderWithScopeSerializer.new(scope: scope) }

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(serializer_factory,
        "scope_value" => scope,
        "foo" => {
          "scope_value" => scope
        })
    end

    it "default scope is nil" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(FooHolderWithScopeSerializer, "scope_value" => nil,
        "foo" => {
          "scope_value" => nil
        })
    end
  end

  context "filter" do
    it "only" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(-> { FooSerializer.new(only: [:name]) }, "name" => foo.name)
    end

    it "except" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(-> { FooSerializer.new(except: [:name]) }, "address" => foo.address)
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

    it "infers the serializer name by name of the realtionship" do
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

    it "infers the serializer name by name of the realtionship" do
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

    it "fetches the the filters from the serializer" do
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

    it 'support nested "only" filter' do
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

  context "serializer reuse" do
    it "raises an error" do
      serializer = FooSerializer.new
      foo_a = Foo.create
      foo_b = Foo.create

      expect { serializer.serialize(foo_a) }.not_to raise_error
      expect { serializer.serialize(foo_b) }.to raise_error(ArgumentError, "Panko::Serializer instances are single-use")
    end
  end

  context "alias" do
    let(:data) { {"created_at" => created_at} }
    let(:created_at) { "2023-04-18T09:24:41+00:00" }

    context "with alias" do
      let(:serializer_class) do
        Class.new(Panko::Serializer) do
          aliases({created_at: :createdAt})
        end
      end

      it "has createdAt" do
        expect(data).to serialized_as(serializer_class,
          "createdAt" => created_at)
      end
    end

    context "with alias + method_fields" do
      let(:serializer_class) do
        Class.new(Panko::Serializer) do
          aliases({created_at: :createdAt})

          def created_at
            "2023-04-18T09:24:41+00:00"
          end
        end
      end

      it "has createdAt" do
        expect(data).to serialized_as(serializer_class,
          "createdAt" => created_at)
      end
    end
  end

  context "key_type" do
    let(:configuration) { Panko::Configuration.new }
    let(:data) { {"created_at" => created_at} }
    let(:created_at) { "2023-04-18T09:24:41+00:00" }

    before do
      allow(Panko).to receive_messages(configuration: configuration)
    end

    context "with camelCase" do
      before { configuration.key_type = "camelCase" }

      context "with key_type" do
        let(:serializer_class) do
          Class.new(Panko::Serializer) do
            attributes :created_at
          end
        end

        it "has createdAt" do
          expect(data).to serialized_as(serializer_class,
            "createdAt" => created_at)
        end
      end

      context "with key_type + method_fields" do
        let(:serializer_class) do
          Class.new(Panko::Serializer) do
            attributes :created_at

            def created_at
              "2023-04-18T09:24:41+00:00"
            end
          end
        end

        it "has createdAt" do
          expect(data).to serialized_as(serializer_class,
            "createdAt" => created_at)
        end
      end

      context "with key_type and alias" do
        let(:serializer_class) do
          Class.new(Panko::Serializer) do
            aliases({created_at: :CreatedAt})
          end
        end

        it "alias has priority over configuration" do
          expect(data).to serialized_as(serializer_class,
            "CreatedAt" => created_at)
        end
      end
    end

    context "with CamelCase" do
      before { configuration.key_type = "CamelCase" }

      context "with key_type" do
        let(:serializer_class) do
          Class.new(Panko::Serializer) do
            attributes :created_at
          end
        end

        it "has CreatedAt" do
          expect(data).to serialized_as(serializer_class,
            "CreatedAt" => created_at)
        end
      end

      context "with key_type + method_fields" do
        let(:serializer_class) do
          Class.new(Panko::Serializer) do
            attributes :created_at

            def created_at
              "2023-04-18T09:24:41+00:00"
            end
          end
        end

        it "has CreatedAt" do
          expect(data).to serialized_as(serializer_class,
            "CreatedAt" => created_at)
        end
      end
    end
  end
end
