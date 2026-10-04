# frozen_string_literal: true

require "spec_helper"

describe "An attribute backed by a SELECT alias" do
  let(:thing_count) { 2 }
  let(:owner) { Owner.create!.tap { |created| thing_count.times { created.things.create! } } }
  let(:alias_value) { 42 }
  let(:aliased_owner) { Owner.select("owners.*, #{alias_value} AS thing_ids").find(owner.id) }
  let(:queries) { [] }

  before do
    Temping.create(:owner) do
      has_many :things
    end

    Temping.create(:thing) do
      with_columns do |t|
        t.integer :owner_id
      end
    end
  end

  let(:serializer_class) do
    stub_const("ThingIdsOwnerSerializer", Class.new(Panko::Serializer) do
      attributes :thing_ids
    end)
  end

  def count_queries
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
  end

  it "reads the alias instead of the association ids reader" do
    record = aliased_owner

    count_queries do
      expect(record).to serialized_as(serializer_class, "thing_ids" => alias_value)
    end

    expect(queries).to be_empty
  end

  it "calls the model method when the alias is not selected" do
    expect(Owner.find(owner.id)).to serialized_as(serializer_class, "thing_ids" => owner.things.ids)
  end

  it "lets a serializer method win over the alias" do
    serializer_method_value = "from serializer"
    serializer = stub_const("MethodThingIdsOwnerSerializer", Class.new(Panko::Serializer) do
      attributes :thing_ids

      define_method(:thing_ids) { serializer_method_value }
    end)

    expect(aliased_owner).to serialized_as(serializer, "thing_ids" => serializer_method_value)
  end

  it "keeps a model reader that overrides a declared attribute" do
    reader_value = "from model reader"
    Owner.attribute :nickname, :string
    Owner.define_method(:nickname) { reader_value }
    serializer = stub_const("NicknameOwnerSerializer", Class.new(Panko::Serializer) do
      attributes :nickname
    end)

    expect(Owner.find(owner.id)).to serialized_as(serializer, "nickname" => reader_value)
  end
end
