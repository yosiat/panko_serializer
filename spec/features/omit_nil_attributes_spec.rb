# frozen_string_literal: true

require "spec_helper"

describe "Omit nil attributes" do
  let(:name) { Faker::Lorem.word }

  # Read when a serializer compiles, so every serializer class is built inside
  # the example, after this hook sets the option.
  around do |example|
    original = Panko::Config.omit_nil_attributes
    Panko::Config.omit_nil_attributes = true
    example.run
  ensure
    Panko::Config.omit_nil_attributes = original
  end

  before do
    Temping.create(:foo) do
      with_columns do |t|
        t.string :name
        t.string :address
        t.boolean :active
        t.datetime :published_at
        t.json :meta
        t.references :foo_holder
      end
    end

    Temping.create(:foo_holder) do
      with_columns do |t|
        t.string :name
      end

      has_one :foo
    end
  end

  let(:foo_serializer) do
    Class.new(Panko::Serializer) do
      attributes :name, :address, :active, :published_at, :meta
    end
  end

  context "with an ActiveRecord record on the specialized path" do
    it "omits nil columns, including datetime and JSON ones" do
      foo = Foo.create(name: name).reload

      expect(foo).to serialized_as(foo_serializer, "name" => name)
      expect(Panko::CodeGen::SerializerCache.specialized?(foo_serializer, :json, Foo)).to be(true)
    end

    it "keeps false, empty and present values" do
      published_at = Time.utc(2026, 1, 2, 3, 4, 5)
      foo = Foo.create(name: "", active: false, published_at: published_at, meta: {"a" => 1}).reload

      expect(foo).to serialized_as(foo_serializer,
        "name" => "",
        "active" => false,
        "published_at" => published_at.as_json,
        "meta" => {"a" => 1})
    end

    it "omits a JSON column that stores the JSON null literal" do
      foo = Foo.create(name: name)
      Foo.where(id: foo.id).update_all("meta = 'null'")
      foo = Foo.find(foo.id)

      expect(foo.read_attribute_before_type_cast("meta")).to eq("null")
      expect(foo).to serialized_as(foo_serializer, "name" => name)
    end

    it "omits nil columns in an ArraySerializer" do
      foos = [Foo.create(name: name), Foo.create(address: "street")].map(&:reload)
      array_serializer = Panko::ArraySerializer.new(foos, each_serializer: foo_serializer)

      expect(Oj.load(array_serializer.to_json)).to eq([{"name" => name}, {"address" => "street"}])
      expect(Panko::ArraySerializer.new(foos, each_serializer: foo_serializer).to_a)
        .to eq([{"name" => name}, {"address" => "street"}])
    end
  end

  context "with the generic path" do
    around do |example|
      original = Panko::Config.auto_specialization.enabled
      Panko::Config.auto_specialization.enabled = false
      example.run
    ensure
      Panko::Config.auto_specialization.enabled = original
    end

    it "omits nil values of an ActiveRecord record" do
      foo = Foo.create(name: name).reload

      expect(foo).to serialized_as(foo_serializer, "name" => name)
    end

    it "omits nil values of a Hash record" do
      foo = {"name" => name, "address" => nil, "active" => false}

      expect(foo).to serialized_as(foo_serializer, "name" => name, "active" => false)
    end

    it "omits nil values of a plain object" do
      foo = Struct.new(:name, :address, :active, :published_at, :meta).new(name)

      expect(foo).to serialized_as(foo_serializer, "name" => name)
    end
  end

  it "keeps a method attribute's nil and SKIP behavior" do
    serializer = Class.new(Panko::Serializer) do
      attributes :name, :nickname, :hidden

      def nickname
        nil
      end

      def hidden
        Panko::Serializer::SKIP
      end
    end

    expect(Foo.create(name: name).reload).to serialized_as(serializer, "name" => name, "nickname" => nil)
  end

  it "keeps null for a missing has_one" do
    child_serializer = foo_serializer
    holder_serializer = Class.new(Panko::Serializer) do
      attributes :name
      has_one :foo, serializer: child_serializer
    end

    expect(FooHolder.create(name: name).reload).to serialized_as(holder_serializer, "name" => name, "foo" => nil)
  end

  it "writes null for nil values when the option is off" do
    Panko::Config.omit_nil_attributes = false
    foo = Foo.create(name: name).reload

    expect(foo).to serialized_as(foo_serializer,
      "name" => name, "address" => nil, "active" => nil, "published_at" => nil, "meta" => nil)
  end
end
