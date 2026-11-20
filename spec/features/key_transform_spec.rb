# frozen_string_literal: true

require "spec_helper"

describe "Key transform" do
  let(:first_name) { Faker::Lorem.word }
  let(:home_address) { Faker::Lorem.word }

  # Read when a serializer declares a field, so every serializer class is
  # built inside the example, after this hook sets the transform.
  around do |example|
    original = Panko::Config.key_transform
    Panko::Config.key_transform = key_transform
    example.run
  ensure
    Panko::Config.key_transform = original
  end

  before do
    Temping.create(:foo) do
      with_columns do |t|
        t.string :first_name
        t.string :home_address
        t.references :foo_holder
      end
    end

    Temping.create(:foo_holder) do
      with_columns do |t|
        t.string :first_name
      end

      has_one :main_foo, class_name: "Foo"
      has_many :foo_items, class_name: "Foo"
    end
  end

  let(:foo_serializer) do
    Class.new(Panko::Serializer) do
      attributes :first_name, :home_address
    end
  end

  context "with :camel_lower" do
    let(:key_transform) { :camel_lower }

    it "lower camelizes the attribute keys of a record" do
      foo = Foo.create(first_name: first_name, home_address: home_address)

      expect(foo).to serialized_as(foo_serializer,
        "firstName" => first_name,
        "homeAddress" => home_address)
    end

    it "reads a Hash record by the declared name" do
      foo = {"first_name" => first_name, "home_address" => home_address}

      expect(foo).to serialized_as(foo_serializer,
        "firstName" => first_name,
        "homeAddress" => home_address)
    end

    it "lower camelizes a method attribute key" do
      serializer = Class.new(Panko::Serializer) do
        attributes :first_name, :display_name

        def display_name
          object.first_name.upcase
        end
      end
      foo = Foo.create(first_name: first_name)

      expect(foo).to serialized_as(serializer,
        "firstName" => first_name,
        "displayName" => first_name.upcase)
    end

    it "keeps an alias as written" do
      serializer = Class.new(Panko::Serializer) do
        attributes :home_address
        aliases first_name: :given_name
      end
      foo = Foo.create(first_name: first_name, home_address: home_address)

      expect(foo).to serialized_as(serializer,
        "homeAddress" => home_address,
        "given_name" => first_name)
    end

    it "lower camelizes association keys and their children's keys" do
      stub_const("FooSerializer", foo_serializer)
      holder_serializer = Class.new(Panko::Serializer) do
        has_one :main_foo, serializer: FooSerializer
        has_many :foo_items, each_serializer: FooSerializer
      end
      holder = FooHolder.create(first_name: first_name)
      foo = Foo.create(first_name: first_name, home_address: home_address, foo_holder_id: holder.id)
      foo_output = {"firstName" => foo.first_name, "homeAddress" => foo.home_address}

      expect(holder).to serialized_as(holder_serializer,
        "mainFoo" => foo_output,
        "fooItems" => [foo_output])
    end

    it "keeps an association name: as written" do
      stub_const("FooSerializer", foo_serializer)
      holder_serializer = Class.new(Panko::Serializer) do
        has_one :main_foo, serializer: FooSerializer, name: :primary_foo
      end
      holder = FooHolder.create(first_name: first_name)
      foo = Foo.create(first_name: first_name, home_address: home_address, foo_holder_id: holder.id)

      expect(holder).to serialized_as(holder_serializer,
        "primary_foo" => {"firstName" => foo.first_name, "homeAddress" => foo.home_address})
    end

    it "filters attributes by the output key" do
      foo = Foo.create(first_name: first_name, home_address: home_address)

      expect(foo).to serialized_as(-> { foo_serializer.new(only: [:firstName]) },
        "firstName" => first_name)
    end

    it "does not match a declared attribute name in a filter" do
      foo = Foo.create(first_name: first_name, home_address: home_address)

      expect(foo).to serialized_as(-> { foo_serializer.new(only: [:first_name]) }, {})
    end

    it "filters associations by the declared name" do
      stub_const("FooSerializer", foo_serializer)
      holder_serializer = Class.new(Panko::Serializer) do
        attributes :first_name
        has_many :foo_items, each_serializer: FooSerializer
      end
      holder = FooHolder.create(first_name: first_name)
      foo = Foo.create(first_name: first_name, home_address: home_address, foo_holder_id: holder.id)

      expect(holder).to serialized_as(
        -> { holder_serializer.new(only: {instance: [:foo_items], foo_items: [:homeAddress]}) },
        "fooItems" => [{"homeAddress" => foo.home_address}]
      )
    end
  end

  context "with :camel" do
    let(:key_transform) { :camel }

    it "camelizes the attribute keys" do
      foo = Foo.create(first_name: first_name, home_address: home_address)

      expect(foo).to serialized_as(foo_serializer,
        "FirstName" => first_name,
        "HomeAddress" => home_address)
    end
  end

  context "with nil" do
    let(:key_transform) { nil }

    it "keeps the declared keys" do
      foo = Foo.create(first_name: first_name, home_address: home_address)

      expect(foo).to serialized_as(foo_serializer,
        "first_name" => first_name,
        "home_address" => home_address)
    end

    it "does not rename a serializer declared before the transform was set" do
      serializer = foo_serializer
      Panko::Config.key_transform = :camel_lower
      foo = Foo.create(first_name: first_name, home_address: home_address)

      expect(foo).to serialized_as(serializer,
        "first_name" => first_name,
        "home_address" => home_address)
    end
  end
end
