# frozen_string_literal: true

require "spec_helper"

describe Panko::Response do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  it "serializes primitive values" do
    response = Panko::Response.new(success: true, num: 1)

    json_response = Oj.load(response.to_json)

    expect(json_response["success"]).to eq(true)
    expect(json_response["num"]).to eq(1)
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
                                       json_data: Panko::JsonValue.from({ a: 1 }.to_json)
                                     )
                                   ])

    json_response = Oj.load(response.to_json)

    expect(json_response).to eql([
                                   { "data" => { "json_data" => { "a" => 1 } } }
                                 ])
  end
end
