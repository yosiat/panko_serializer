# frozen_string_literal: true

require "spec_helper"

describe Panko::Response do
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

  let(:foo_with_context_serializer_class) do
    Class.new(Panko::Serializer) do
      attributes :name, :context_value

      def context_value
        context[:value]
      end
    end
  end

  before do
    stub_const("FooSerializer", foo_serializer_class)
    stub_const("FooWithContextSerializer", foo_with_context_serializer_class)
  end

  it "serializes primitive values" do
    response = Panko::Response.new(success: true, num: 1)

    json_response = Oj.load(response.to_json)

    expect(json_response["success"]).to eq(true)
    expect(json_response["num"]).to eq(1)
  end

  it "serializes hash values" do
    hash = {"a" => 1, "b" => 2}
    response = Panko::Response.new(success: true, hash: hash)

    json_response = Oj.load(response.to_json)

    expect(json_response["hash"]).to eq(hash)
  end

  it "serializes json wrapped in json value" do
    response = Panko::Response.new(success: true, value: Panko::JsonValue.from('{"a":1}'))

    json_response = Oj.load(response.to_json)

    expect(json_response["success"]).to eq(true)
    expect(json_response["value"]).to eq("a" => 1)
  end

  it "serializes array serializer" do
    foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

    response = Panko::Response.new(success: true,
      foos: Panko::ArraySerializer.new(Foo.all, each_serializer: FooSerializer))

    json_response = Oj.load(response.to_json)

    expect(json_response["success"]).to eq(true)
    expect(json_response["foos"]).to eq([
      "name" => foo.name,
      "address" => foo.address
    ])
  end

  it "supports nesting of responses" do
    foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

    response = Panko::Response.new(
      data: Panko::Response.new(
        data: Panko::Response.new(
          rows: [
            Panko::Response.new(
              foos: Panko::ArraySerializer.new(Foo.all, each_serializer: FooSerializer)
            )
          ]
        )
      )
    )

    json_response = Oj.load(response.to_json)

    expect(json_response).to eq(
      "data" => {
        "data" => {
          "rows" => [
            "foos" => [{
              "name" => foo.name,
              "address" => foo.address
            }]
          ]
        }
      }
    )
  end

  it "supports array" do
    response = Panko::Response.new([
      data: Panko::Response.new(
        json_data: Panko::JsonValue.from({a: 1}.to_json)
      )
    ])

    json_response = Oj.load(response.to_json)

    expect(json_response).to eql([
      {"data" => {"json_data" => {"a" => 1}}}
    ])
  end

  it "create" do
    foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

    response = Panko::Response.create do |t|
      [
        {
          data: t.value(
            json_data: t.json({a: 1}.to_json),
            foos: t.array_serializer(Foo.all, FooSerializer),
            foo: t.serializer(Foo.first, FooSerializer)
          )
        }
      ]
    end

    json_response = Oj.load(response.to_json)

    expect(json_response).to eql([
      {"data" =>
        {
          "json_data" => {"a" => 1},
          "foo" => {
            "name" => foo.name,
            "address" => foo.address
          },
          "foos" => [{
            "name" => foo.name,
            "address" => foo.address
          }]
        }}
    ])
  end

  it "create with context" do
    foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
    context = {value: Faker::Lorem.word}

    response = Panko::Response.create do |t|
      [
        {
          data: t.value(
            foos: t.array_serializer(Foo.all, FooWithContextSerializer, context: context),
            foo: t.serializer(Foo.first, FooWithContextSerializer, context: context)
          )
        }
      ]
    end

    json_response = Oj.load(response.to_json)

    expect(json_response).to eql([
      {"data" =>
        {
          "foo" => {
            "name" => foo.name,
            "context_value" => context[:value]
          },
          "foos" => [{
            "name" => foo.name,
            "context_value" => context[:value]
          }]
        }}
    ])
  end

  describe "output bytes" do
    let(:foo) { Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word) }
    let(:context) { {value: Faker::Lorem.word} }

    before { foo }

    it "writes an array serializer as the bytes of its to_json" do
      array = Panko::ArraySerializer.new(Foo.all, each_serializer: FooWithContextSerializer, context: context, only: [:context_value])

      expect(Panko::Response.new(success: true, foos: array).to_json).to eq(%({"success":true,"foos":#{array.to_json}}\n))
    end

    it "writes an empty array serializer" do
      array = Panko::ArraySerializer.new(Foo.none, each_serializer: FooSerializer)

      expect(Panko::Response.new(foos: array).to_json).to eq(%({"foos":[]}\n))
    end

    it "writes a serializer from create as the bytes of serialize_to_json" do
      response = Panko::Response.create { |r| {foo: r.serializer(foo, FooWithContextSerializer, context: context)} }
      expected = FooWithContextSerializer.new(context: context).serialize_to_json(foo)

      expect(response.to_json).to eq(%({"foo":#{expected}}\n))
    end

    it "writes serializers from create as array elements" do
      response = Panko::Response.create { |r| [r.serializer(foo, FooSerializer), r.serializer(foo, FooSerializer)] }
      expected = FooSerializer.new.serialize_to_json(foo)

      expect(response.to_json).to eq("[#{expected},#{expected}]\n")
    end

    it "writes a nested response inside an array" do
      array = Panko::ArraySerializer.new(Foo.all, each_serializer: FooSerializer)
      response = Panko::Response.new(rows: [Panko::Response.new(foos: array)])

      expect(response.to_json).to eq(%({"rows":[{"foos":#{array.to_json}}]}\n))
    end

    it "returns the same bytes on a second call" do
      response = Panko::Response.new(foos: Panko::ArraySerializer.new(Foo.all, each_serializer: FooSerializer))

      expect(response.to_json).to eq(response.to_json)
    end

    it "keeps no output of a call that raised" do
      failing_serializer = Class.new(Panko::Serializer) do
        attributes :boom

        def boom
          raise ArgumentError
        end
      end
      stub_const("FailingSerializer", failing_serializer)
      failing = Panko::Response.new(foos: Panko::ArraySerializer.new(Foo.all, each_serializer: FailingSerializer))

      expect { failing.to_json }.to raise_error(ArgumentError)
      expect(Panko::Response.new(success: true).to_json).to eq(%({"success":true}\n))
    end
  end

  describe Panko::SerializerValue do
    it "returns the bytes of serialize_to_json from to_json" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      value = Panko::ResponseCreator.serializer(foo, FooSerializer)

      expect(value.to_json).to eq(FooSerializer.new.serialize_to_json(foo))
    end
  end
end
