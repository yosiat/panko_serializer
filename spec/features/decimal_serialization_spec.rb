# frozen_string_literal: true

require "spec_helper"

describe "Decimal column serialization" do
  let(:price_string) { "42.5" }
  let(:foo) { Foo.create(price: BigDecimal(price_string)).reload }
  let(:expected_price) { foo.price.as_json }

  before do
    Temping.create(:foo) do
      with_columns do |t|
        t.decimal :price
      end
    end
  end

  around do |example|
    original_enabled = Panko::Config.auto_specialization.enabled
    example.run
  ensure
    Panko::Config.auto_specialization.enabled = original_enabled
  end

  let(:serializer_class) do
    stub_const("DecimalFooSerializer", Class.new(Panko::Serializer) do
      attributes :price
    end)
  end

  let(:generic_serializer_class) do
    stub_const("GenericDecimalFooSerializer", Class.new(Panko::Serializer) do
      attributes :price
    end)
  end

  it "renders the 0.8.5 String on the specialized hash path" do
    expect(serializer_class.new.serialize(foo)).to eq("price" => expected_price)
  end

  it "renders the 0.8.5 String on the generic hash path" do
    Panko::Config.auto_specialization.enabled = false

    expect(generic_serializer_class.new.serialize(foo)).to eq("price" => expected_price)
  end

  it "produces byte-identical JSON on both paths" do
    specialized_json = serializer_class.new.serialize_to_json(foo)

    Panko::Config.auto_specialization.enabled = false
    generic_json = generic_serializer_class.new.serialize_to_json(foo)

    expect(specialized_json).to eq(generic_json)
  end
end
