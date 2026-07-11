# frozen_string_literal: true

require "spec_helper"

describe "Panko::CodeGen::DescriptorBuilder.specialize" do
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

  let(:bar_serializer) do
    stub_const("BarSerializer", Class.new(Panko::Serializer) do
      attributes :label
    end)
  end

  def descriptor_for(serializer_class)
    Panko::CodeGen::SerializerCache.descriptor_for(serializer_class)
  end

  def specialize(descriptor, model)
    Panko::CodeGen::DescriptorBuilder.specialize(descriptor, model)
  end

  it "fills the root Model and the reflected child Model" do
    bar_serializer
    foo_serializer = stub_const("FooSerializer", Class.new(Panko::Serializer) do
      attributes :name
      has_many :bars, serializer: BarSerializer
    end)

    specialized = specialize(descriptor_for(foo_serializer), Foo)

    expect(specialized.model).to eq(Foo)
    expect(specialized.associations.first.descriptor.model).to eq(Bar)
  end

  it "leaves a child that declared its own Model untouched" do
    stub_const("DeclaredBarSerializer", Class.new(Panko::Serializer) do
      models [Bar]
      attributes :label
    end)
    foo_serializer = stub_const("FooSerializer", Class.new(Panko::Serializer) do
      attributes :name
      has_many :bars, serializer: DeclaredBarSerializer
    end)
    descriptor = descriptor_for(foo_serializer)

    specialized = specialize(descriptor, Foo)

    expect(specialized.associations.first).to be(descriptor.associations.first)
    expect(specialized.associations.first.descriptor.model).to eq(Bar)
  end

  it "leaves a plain-method association source on the Generic path" do
    bar_serializer
    Foo.class_eval do
      def fancy_bars
        bars
      end
    end
    foo_serializer = stub_const("FooSerializer", Class.new(Panko::Serializer) do
      attributes :name
      has_many :fancy_bars, serializer: BarSerializer
    end)
    descriptor = descriptor_for(foo_serializer)

    specialized = specialize(descriptor, Foo)

    expect(specialized.model).to eq(Foo)
    expect(specialized.associations.first).to be(descriptor.associations.first)
    expect(specialized.associations.first.descriptor.model).to be_nil
  end

  it "leaves a polymorphic reflection on the Generic path" do
    Temping.create(:tag) do
      with_columns do |t|
        t.string :value
        t.bigint :subject_id
        t.string :subject_type
      end
    end
    Tag.belongs_to :subject, polymorphic: true
    stub_const("SubjectSerializer", Class.new(Panko::Serializer) do
      attributes :id
    end)
    tag_serializer = stub_const("TagSerializer", Class.new(Panko::Serializer) do
      attributes :value
      has_one :subject, serializer: SubjectSerializer
    end)
    descriptor = descriptor_for(tag_serializer)

    specialized = specialize(descriptor, Tag)

    expect(specialized.model).to eq(Tag)
    expect(specialized.associations.first.descriptor.model).to be_nil
  end

  it "leaves an unresolvable class_name reflection on the Generic path" do
    bar_serializer
    Foo.has_many :ghosts, class_name: "GhostNotDefined", foreign_key: :foo_id
    foo_serializer = stub_const("FooSerializer", Class.new(Panko::Serializer) do
      attributes :name
      has_many :ghosts, serializer: BarSerializer
    end)
    descriptor = descriptor_for(foo_serializer)

    specialized = specialize(descriptor, Foo)

    expect(specialized.model).to eq(Foo)
    expect(specialized.associations.first.descriptor.model).to be_nil
  end
end
