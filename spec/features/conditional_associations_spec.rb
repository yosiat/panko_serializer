# frozen_string_literal: true

require "spec_helper"

describe "Conditional associations" do
  before do
    Temping.create(:foo) do
      with_columns do |t|
        t.string :name
        t.references :foos_holder
      end
    end

    Temping.create(:foos_holder) do
      with_columns do |t|
        t.string :name
        t.references :foo
      end

      has_many :foos
      belongs_to :foo, optional: true
    end

    stub_const("FooSerializer", Class.new(Panko::Serializer) { attributes :name })
  end

  let(:foo) { Foo.create(name: "child") }
  let(:holder) { FoosHolder.create(name: "parent", foo: foo, foos: [Foo.create(name: "a")]).reload }

  def both_modes(serializer, record, **options)
    [
      serializer.new(**options).serialize(record),
      Oj.load(serializer.new(**options).serialize_to_json(record))
    ]
  end

  it "keeps a has_one when if: is truthy and omits the key when falsy" do
    serializer = Class.new(Panko::Serializer) do
      attributes :name
      has_one :foo, serializer: FooSerializer, if: ->(_record, context) { context[:show] }
    end

    both_modes(serializer, holder, context: {show: true}).each do |output|
      expect(output).to eq("name" => "parent", "foo" => {"name" => "child"})
    end
    both_modes(serializer, holder, context: {show: false}).each do |output|
      expect(output).to eq("name" => "parent")
    end
  end

  it "keeps a has_many when if: is truthy and omits the key when falsy" do
    serializer = Class.new(Panko::Serializer) do
      attributes :name
      has_many :foos, each_serializer: FooSerializer, if: ->(record) { record.name == "parent" }
    end
    other = FoosHolder.create(name: "other", foos: [Foo.create(name: "b")]).reload

    both_modes(serializer, holder).each do |output|
      expect(output).to eq("name" => "parent", "foos" => [{"name" => "a"}])
    end
    both_modes(serializer, other).each do |output|
      expect(output).to eq("name" => "other")
    end
  end

  it "passes record, context and scope to a three-argument if:" do
    serializer = Class.new(Panko::Serializer) do
      attributes :name
      has_one :foo, serializer: FooSerializer, if: ->(_record, _context, scope) { scope == :admin }
    end

    both_modes(serializer, holder, scope: :admin).each do |output|
      expect(output).to include("foo" => {"name" => "child"})
    end
    both_modes(serializer, holder, scope: :guest).each do |output|
      expect(output).not_to have_key("foo")
    end
  end

  it "does not read the association when if: is falsy" do
    record = Struct.new(:name) do
      def foo = raise("association read")
    end.new("plain")
    serializer = Class.new(Panko::Serializer) do
      attributes :name
      has_one :foo, serializer: FooSerializer, if: -> { false }
    end

    both_modes(serializer, record).each do |output|
      expect(output).to eq("name" => "plain")
    end
  end

  it "rejects an if: that is not callable" do
    expect {
      Class.new(Panko::Serializer) do
        has_one :foo, serializer: FooSerializer, if: :admin?
      end
    }.to raise_error(Panko::CodeGen::DescriptorError, /Association#if/)
  end
end
