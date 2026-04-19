# frozen_string_literal: true

require "spec_helper"

# Coverage for the E5 unrolled non-indexed branch of +_write_ar_fallback+.
# The branch runs when a record is not backed by +ActiveRecord::Result::IndexedRow+
# (unpersisted record, Rails 7.x query results without IndexedRow, a record with
# a dirty +@attributes+ hash, etc). Prior to E5 this was a pre-written
# +each_with_index+ loop on {Panko::CodeGen::GeneratedBase}; E5 unrolls it
# per-serializer so YJIT can inline each per-attribute read + dispatch.
describe "E5 unrolled _write_ar_fallback" do
  before do
    Temping.create(:e5_user) do
      with_columns do |t|
        t.string :name
        t.string :address
        t.integer :merchant_id
      end
    end
  end

  class E5UserSerializer < Panko::Serializer
    attributes :name, :address, :merchant_id
  end

  describe "unpersisted record (no IndexedRow backing)" do
    it "serializes all attributes via the unrolled non-indexed branch" do
      user = E5User.new(name: "opus", address: "addr", merchant_id: 42)

      json = E5UserSerializer.new.serialize_to_json(user)
      expect(Oj.load(json)).to eq(
        "name" => "opus",
        "address" => "addr",
        "merchant_id" => 42
      )
    end

    it "handles nil attribute values" do
      user = E5User.new(name: nil, address: "addr", merchant_id: nil)

      json = E5UserSerializer.new.serialize_to_json(user)
      expect(Oj.load(json)).to eq(
        "name" => nil,
        "address" => "addr",
        "merchant_id" => nil
      )
    end

    it "reflects in-memory mutations" do
      user = E5User.new(name: "opus", address: "addr", merchant_id: 1)
      user.name = "yosi"

      json = E5UserSerializer.new.serialize_to_json(user)
      expect(Oj.load(json)["name"]).to eq("yosi")
    end
  end

  describe "persisted record after mutation (dirty attributes hash)" do
    it "serializes via the indexed branch of fallback (with dirty check)" do
      E5User.create!(name: "original", address: "addr-a", merchant_id: 10)
      user = E5User.first
      user.name = "mutated"

      json = E5UserSerializer.new.serialize_to_json(user)
      expect(Oj.load(json)).to eq(
        "name" => "mutated",
        "address" => "addr-a",
        "merchant_id" => 10
      )
    end
  end

  describe "aliased attributes" do
    class E5AliasedSerializer < Panko::Serializer
      aliases name: :display_name
      attributes :address
    end

    it "routes via name_for_serialization for unpersisted records" do
      user = E5User.new(name: "opus", address: "addr", merchant_id: 1)

      json = E5AliasedSerializer.new.serialize_to_json(user)
      expect(Oj.load(json)).to eq("display_name" => "opus", "address" => "addr")
    end
  end

  describe "AR column aliases (via attribute_aliases)" do
    # +handle_class_change+ rewrites +attr.name+ when the record class declares
    # +alias_attribute+. The unrolled fallback must read +@_attr_#{i}.name+ at
    # call time (via +rs.read_attribute+) not at build time — otherwise the
    # rewrite is lost.
    before do
      Temping.create(:e5_ar_aliased) do
        with_columns do |t|
          t.string :real_name
        end
        alias_attribute :nickname, :real_name
      end
    end

    class E5ArAliasedSerializer < Panko::Serializer
      attributes :nickname
    end

    it "reads the aliased column through the rewritten attribute name" do
      record = E5ArAliased.new(real_name: "opus")

      json = E5ArAliasedSerializer.new.serialize_to_json(record)
      expect(Oj.load(json)).to eq("nickname" => "opus")
    end
  end

  describe "empty serializer (no attributes)" do
    class E5EmptySerializer < Panko::Serializer
    end

    it "serializes to an empty object without raising" do
      user = E5User.new(name: "opus")

      json = E5EmptySerializer.new.serialize_to_json(user)
      expect(Oj.load(json)).to eq({})
    end
  end

  describe "partial select on non-indexed path" do
    # On the non-indexed path +rs.read_attribute+ handles missing columns by
    # returning nil; the unrolled fallback should pass that through without
    # raising.
    it "returns nil for unselected columns", if: defined?(::ActiveRecord::Result::IndexedRow) do
      E5User.create!(name: "opus", address: "addr-a", merchant_id: 10)
      record = E5User.select(:id, :merchant_id).first
      # Trigger the fallback path: mutate to force the dirty attributes hash.
      record.merchant_id = 99

      json = E5UserSerializer.new.serialize_to_json(record)
      parsed = Oj.load(json)
      expect(parsed["merchant_id"]).to eq(99)
      expect(parsed["name"]).to be_nil
      expect(parsed["address"]).to be_nil
    end
  end
end
