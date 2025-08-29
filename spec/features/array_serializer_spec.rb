# frozen_string_literal: true

require "spec_helper"

describe Panko::ArraySerializer do
  before do
    Temping.create(:foo) do
      with_columns do |t|
        t.string :name
        t.string :address
      end
    end
  end

  let(:foo_serializer_class) do
    Class.new(Panko::Serializer) do
      attributes :name, :address
    end
  end

  before { stub_const("FooSerializer", foo_serializer_class) }

  it "throws argument error when each_serializer isnt passed" do
    expect do
      Panko::ArraySerializer.new([])
    end.to raise_error(ArgumentError)
  end

  context "sanity" do
    it "serializers array of elements" do
      array_serializer_factory = -> { Panko::ArraySerializer.new([], each_serializer: FooSerializer) }

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(Foo.all).to serialized_as(array_serializer_factory, [
        {"name" => foo1.name, "address" => foo1.address},
        {"name" => foo2.name, "address" => foo2.address}
      ])
    end

    it "serializes array of elements with virtual attribtues" do
      class TestSerializerWithMethodsSerializer < Panko::Serializer
        attributes :name, :address, :something, :context_fetch

        def something
          "#{object.name} #{object.address}"
        end

        def context_fetch
          context[:value]
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      array_serializer_factory = -> {
        Panko::ArraySerializer.new([],
          each_serializer: TestSerializerWithMethodsSerializer,
          context: {value: 6})
      }

      expect(Foo.all).to serialized_as(array_serializer_factory, [{"name" => foo.name,
                                                                   "address" => foo.address,
                                                                   "something" => "#{foo.name} #{foo.address}",
                                                                   "context_fetch" => 6}])
    end
  end

  context "filter" do
    it "only" do
      array_serializer_factory = -> { Panko::ArraySerializer.new([], each_serializer: FooSerializer, only: [:name]) }

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(Foo.all).to serialized_as(array_serializer_factory, [
        {"name" => foo1.name},
        {"name" => foo2.name}
      ])
    end

    it "except" do
      array_serializer_factory = -> { Panko::ArraySerializer.new([], each_serializer: FooSerializer, except: [:name]) }

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(Foo.all).to serialized_as(array_serializer_factory, [
        {"address" => foo1.address},
        {"address" => foo2.address}
      ])
    end
  end
end
