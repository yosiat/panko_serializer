# frozen_string_literal: true

require "spec_helper"

describe "Datetime serialization" do
  let(:name) { "Jane Doe" }
  let(:foo) { Foo.create(name: name).reload }
  let(:expected_created_at) { foo.created_at.as_json }

  before do
    Temping.create(:foo) do
      with_columns do |t|
        t.string :name
        t.timestamps
      end
    end
  end

  let(:specialized_serializer) do
    stub_const("DatetimeSpecializedFooSerializer", Class.new(Panko::Serializer) do
      models [Foo]
      attributes :name, :created_at
    end)
  end

  let(:generic_serializer) do
    stub_const("DatetimeGenericFooSerializer", Class.new(Panko::Serializer) do
      attributes :name, :created_at
    end)
  end

  it "renders the ISO-8601 String on the specialized JSON fast path" do
    result = Oj.load(specialized_serializer.new.serialize_to_json(foo))

    expect(result).to eq("name" => name, "created_at" => expected_created_at)
  end

  it "renders the ISO-8601 String on the specialized hash path" do
    expect(specialized_serializer.new.serialize(foo))
      .to eq("name" => name, "created_at" => expected_created_at)
  end

  it "produces byte-identical JSON to the generic path" do
    expect(specialized_serializer.new.serialize_to_json(foo))
      .to eq(generic_serializer.new.serialize_to_json(foo))
  end

  it "falls back to the type-cast read for a dirty (unsaved) datetime" do
    dirty_time = Time.utc(2030, 1, 2, 3, 4, 5)
    unsaved = Foo.new(name: name, created_at: dirty_time)

    result = Oj.load(specialized_serializer.new.serialize_to_json(unsaved))

    expect(result["created_at"]).to eq(dirty_time.as_json)
  end

  it "renders nil for a nil datetime column" do
    unsaved = Foo.new(name: name)

    expect(specialized_serializer.new.serialize(unsaved))
      .to eq("name" => name, "created_at" => nil)
    expect(Oj.load(specialized_serializer.new.serialize_to_json(unsaved)))
      .to eq("name" => name, "created_at" => nil)
  end
end
