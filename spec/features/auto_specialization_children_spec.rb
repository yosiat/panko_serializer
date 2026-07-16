# frozen_string_literal: true

require "spec_helper"

describe "Auto-specialization — children via reflections" do
  let(:name) { "Jane Doe" }
  let(:label) { "first" }
  let(:other_label) { "second" }
  let(:foo) do
    record = Foo.create(name: name)
    record.bars.create(label: label)
    record.bars.create(label: other_label)
    record.reload
  end
  let(:expected) do
    {"name" => name, "bars" => [{"label" => label}, {"label" => other_label}]}
  end

  before do
    Temping.create(:foo) do
      with_columns do |t|
        t.string :name
      end
    end
    Temping.create(:bar) do
      with_columns do |t|
        t.string :label
        t.bigint :foo_id
      end
    end
    Foo.has_many :bars
    Bar.belongs_to :foo, optional: true
  end

  around do |example|
    original_enabled = Panko::Config.auto_specialization.enabled
    example.run
  ensure
    Panko::Config.auto_specialization.enabled = original_enabled
  end

  let(:serializer_class) do
    stub_const("ChildBarSerializer", Class.new(Panko::Serializer) do
      attributes :label
    end)
    stub_const("ParentFooSerializer", Class.new(Panko::Serializer) do
      attributes :name
      has_many :bars, serializer: ChildBarSerializer
    end)
  end

  def generic_output(record)
    Panko::Config.auto_specialization.enabled = false
    generic = stub_const("GenericParentFooSerializer", Class.new(Panko::Serializer) do
      attributes :name
      has_many :bars, serializer: ChildBarSerializer
    end)
    output = generic.new.serialize_to_json(record)
    Panko::Config.auto_specialization.enabled = true
    output
  end

  it "serializes an association tree byte-identically to the generic path" do
    expect(serializer_class.new.serialize_to_json(foo)).to eq(generic_output(foo))
    expect(Oj.load(serializer_class.new.serialize_to_json(foo))).to eq(expected)
  end

  it "compiles a specialized variant for the root on first sight" do
    serializer_class.new.serialize_to_json(foo)

    expect(Panko::CodeGen::SerializerCache.specialized?(serializer_class, :json, Foo)).to be(true)
  end

  it "keeps output correct when an association reader returns non-reflected objects" do
    duck_bar = Struct.new(:label)
    Foo.class_eval do
      define_method(:bars) { [duck_bar.new("duck")] }
    end
    record = Foo.create(name: name).reload

    output = Oj.load(serializer_class.new.serialize_to_json(record))

    expect(output).to eq("name" => name, "bars" => [{"label" => "duck"}])
  end
end
