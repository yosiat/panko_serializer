# frozen_string_literal: true

require "spec_helper"

# Regression coverage for +_write_indexed_cached+ when the record was loaded
# with +.select(:a_subset)+ so +column_indexes+ does not contain every
# attribute the serializer knows about.  Before the guard on +@_col_#{i}+,
# generated code did +row[nil]+ and raised TypeError.
describe "Partial-select serialization" do
  before do
    Temping.create(:merchant) do
      with_columns do |t|
        t.string :name
        t.string :address
        t.integer :merchant_id
      end
    end
  end

  class PartialSelectSerializer < Panko::Serializer
    attributes :name, :address, :merchant_id
  end

  it "returns nil for unselected columns (first pass and warmed cached path)" do
    Merchant.create!(name: "A", address: "addr-a", merchant_id: 10)
    Merchant.create!(name: "B", address: "addr-b", merchant_id: 20)

    records = Merchant.select(:id, :merchant_id).order(:id).to_a

    # First call exercises the pre-written +_write_indexed_first_pass+ path
    # and triggers +build_caches!+ which stamps +@_col_#{i} = nil+ for
    # columns that were not selected.
    first = Panko::ArraySerializer.new(records, each_serializer: PartialSelectSerializer).to_a
    expect(first[0]).to eq("name" => nil, "address" => nil, "merchant_id" => 10)
    expect(first[1]).to eq("name" => nil, "address" => nil, "merchant_id" => 20)

    # Second call exercises the hot +_write_indexed_cached+ path with the
    # stamped nil column indices.  Must not raise TypeError.
    records_again = Merchant.select(:id, :merchant_id).order(:id).to_a
    second = Panko::ArraySerializer.new(records_again, each_serializer: PartialSelectSerializer).to_a
    expect(second[0]).to eq("name" => nil, "address" => nil, "merchant_id" => 10)
    expect(second[1]).to eq("name" => nil, "address" => nil, "merchant_id" => 20)
  end

  it "returns nil for unselected columns via to_json (Oj::StringWriter path)" do
    Merchant.create!(name: "A", address: "addr-a", merchant_id: 10)
    records = Merchant.select(:id, :merchant_id).to_a

    json = Panko::ArraySerializer.new(records, each_serializer: PartialSelectSerializer).to_json
    parsed = Oj.load(json)
    expect(parsed[0]).to eq("name" => nil, "address" => nil, "merchant_id" => 10)
  end
end
