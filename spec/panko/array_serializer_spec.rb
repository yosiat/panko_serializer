# frozen_string_literal: true

require "spec_helper"

describe Panko::ArraySerializer do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  it "throws argument error when each_serializer isnt passed" do
    expect {
      Panko::ArraySerializer.new([])
    }.to raise_error(ArgumentError)
  end

  context "sanity" do
    it "serializers array of elements" do
      array_serializer = Panko::ArraySerializer.new([], each_serializer: FooSerializer)

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      output = array_serializer.serialize Foo.all

      expect(output).to eq([
                             { "name" => foo1.name, "address" => foo1.address },
                             { "name" => foo2.name, "address" => foo2.address }
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

     foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

     array_serializer = Panko::ArraySerializer.new([],
                                                  each_serializer: TestSerializerWithMethodsSerializer,
                                                  context: { value: 6 })

     output = array_serializer.serialize Foo.all

     expect(output.first).to eq("name" => foo.name,
                                "address" => foo.address,
                                "something" => "#{foo.name} #{foo.address}",
                                "context_fetch" => 6)
    end
  end

  context "filter" do
    it "only" do
      array_serializer = Panko::ArraySerializer.new([], each_serializer: FooSerializer, only: [:name])

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      output = array_serializer.serialize Foo.all

      expect(output).to eq([
                             { "name" => foo1.name },
                             { "name" => foo2.name }
                           ])
    end

    it "except" do
      array_serializer = Panko::ArraySerializer.new([], each_serializer: FooSerializer, except: [:name])

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      output = array_serializer.serialize Foo.all

      expect(output).to eq([
                             { "address" => foo1.address },
                             { "address" => foo2.address }
                           ])
    end
  end
end
