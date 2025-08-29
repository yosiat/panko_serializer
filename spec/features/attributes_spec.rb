# frozen_string_literal: true

require "spec_helper"

describe "Attributes Serialization" do
  context "instance variables" do
    it "serializes instance variables" do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end

      class FooSerializer < Panko::Serializer
        attributes :name, :address
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(FooSerializer,
        "name" => foo.name,
        "address" => foo.address)
    end
  end

  context "method attributes" do
    it "serializes method attributes" do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end

      class FooWithMethodsSerializer < Panko::Serializer
        attributes :name, :address, :something

        def something
          "#{object.name} #{object.address}"
        end

        def another_method
          raise "I shouldn't get called"
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(FooWithMethodsSerializer, "name" => foo.name,
        "address" => foo.address,
        "something" => "#{foo.name} #{foo.address}")
    end
  end

  context "inheritance" do
    it "supports serializer inheritance" do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end

      class BaseSerializer < Panko::Serializer
        attributes :name
      end

      class ChildSerializer < BaseSerializer
        attributes :address
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(ChildSerializer, "name" => foo.name,
        "address" => foo.address)
    end
  end

  context "time serialization" do
    it "serializes time correctly" do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
          t.timestamps
        end
      end

      class ObjectWithTimeSerializer < Panko::Serializer
        attributes :created_at, :method

        def method
          object.created_at
        end
      end

      obj = Foo.create

      expect(obj).to serialized_as(ObjectWithTimeSerializer,
        "created_at" => obj.created_at.as_json,
        "method" => obj.created_at.as_json)
    end
  end

  context "type handling" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :value
        end
      end
    end

    it "honors additional types" do
      class FooValueSerializer < Panko::Serializer
        attributes :value
      end

      foo = Foo.instantiate({"value" => "1"},
        "value" => ActiveRecord::Type::Integer.new)

      expect(foo).to serialized_as(FooValueSerializer, "value" => 1)
    end
  end

  context "aliases" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end
    end

    it "supports active record alias attributes" do
      class FooWithAliasesModel < ActiveRecord::Base
        self.table_name = "foos"
        alias_attribute :full_name, :name
      end

      class FooWithArAliasesSerializer < Panko::Serializer
        attributes :full_name, :address
      end

      foo = FooWithAliasesModel.create(full_name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(FooWithArAliasesSerializer, "full_name" => foo.name, "address" => foo.address)
    end

    it "allows to alias attributes" do
      class FooWithAliasesSerializer < Panko::Serializer
        attributes :address

        aliases name: :full_name
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(FooWithAliasesSerializer, "full_name" => foo.name, "address" => foo.address)
    end

    context "alias with method_fields" do
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
  end

  context "null values" do
    it "serializes null values" do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end

      class FooSerializer < Panko::Serializer
        attributes :name, :address
      end

      expect(Foo.create).to serialized_as(FooSerializer, "name" => nil, "address" => nil)
    end
  end

  context "SKIP functionality" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end
    end

    it "can skip fields" do
      class FooSkipSerializer < FooSerializer
        def address
          object.address || SKIP
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      expect(foo).to serialized_as(FooSkipSerializer, "name" => foo.name, "address" => foo.address)

      foo = Foo.create(name: Faker::Lorem.word, address: nil)
      expect(foo).to serialized_as(FooSkipSerializer, "name" => foo.name)
    end
  end

  context "serializer reuse" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end
    end

    it "raises an error when reusing serializer instances" do
      class FooSerializer < Panko::Serializer
        attributes :name, :address
      end

      serializer = FooSerializer.new
      foo_a = Foo.create
      foo_b = Foo.create

      expect { serializer.serialize(foo_a) }.not_to raise_error
      expect { serializer.serialize(foo_b) }.to raise_error(ArgumentError, "Panko::Serializer instances are single-use")
    end
  end
end
