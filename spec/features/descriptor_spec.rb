# frozen_string_literal: true

require "spec_helper"

describe "Panko::Descriptor" do
  context "class-level descriptor" do
    let(:foo_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :address
        aliases title: :headline
      end
    end

    before { stub_const("FooSerializer", foo_serializer_class) }

    it "exposes the serializer class and its attributes" do
      descriptor = FooSerializer.descriptor

      expect(descriptor.serializer).to eq(FooSerializer)
      expect(descriptor.attributes.map(&:name)).to eq(%i[name address headline])
      expect(descriptor.attributes.map(&:source)).to eq(%i[name address title])
    end

    context "method attributes" do
      let(:foo_serializer_class) do
        Class.new(Panko::Serializer) do
          attributes :name, :address
          aliases title: :headline

          def address
            "fixed address"
          end

          def title
            "fixed title"
          end
        end
      end

      it "exposes user-defined methods as method attributes keyed by method name" do
        descriptor = FooSerializer.descriptor

        expect(descriptor.attributes.map(&:name)).to eq(%i[name])
        expect(descriptor.method_attributes.map(&:name)).to eq(%i[address headline])
        expect(descriptor.method_attributes.map(&:source)).to eq(%i[address title])
      end
    end

    context "associations" do
      let(:holder_serializer_class) do
        Class.new(Panko::Serializer) do
          attributes :name

          has_one :foo, serializer: FooSerializer, name: :renamed_foo
          has_many :foos, serializer: FooSerializer
        end
      end

      before { stub_const("HolderSerializer", holder_serializer_class) }

      it "exposes associations with their kind, source, and nested descriptor" do
        descriptor = HolderSerializer.descriptor

        expect(descriptor.associations.map(&:name)).to eq(%i[renamed_foo foos])
        expect(descriptor.associations.map(&:source)).to eq(%i[foo foos])
        expect(descriptor.associations.map(&:kind)).to eq(%i[has_one has_many])

        nested = descriptor.associations.first.descriptor
        expect(nested.serializer).to eq(FooSerializer)
        expect(nested.attributes.map(&:name)).to eq(%i[name address headline])
      end
    end
  end

  context "instance-level descriptor" do
    let(:foo_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :address
      end
    end

    before { stub_const("FooSerializer", foo_serializer_class) }

    context "without filters" do
      it "returns the identity-same cached class-level view" do
        expect(FooSerializer.new.descriptor).to equal(FooSerializer.descriptor)
      end
    end

    context "with only" do
      it "keeps only the whitelisted fields" do
        descriptor = FooSerializer.new(only: [:name]).descriptor

        expect(descriptor.serializer).to eq(FooSerializer)
        expect(descriptor.attributes.map(&:name)).to eq(%i[name])
      end
    end

    context "with except" do
      it "drops the blacklisted fields" do
        descriptor = FooSerializer.new(except: [:name]).descriptor

        expect(descriptor.attributes.map(&:name)).to eq(%i[address])
      end
    end

    context "with filters_for" do
      let(:foo_serializer_class) do
        Class.new(Panko::Serializer) do
          attributes :name, :address

          def self.filters_for(_context, _scope)
            {only: [:address]}
          end
        end
      end

      it "applies the class-level filter overrides" do
        expect(FooSerializer.new.descriptor.attributes.map(&:name)).to eq(%i[address])
      end
    end

    context "with association filters" do
      let(:holder_serializer_class) do
        Class.new(Panko::Serializer) do
          attributes :name

          has_many :foos, serializer: FooSerializer
        end
      end

      before { stub_const("HolderSerializer", holder_serializer_class) }

      it "narrows the current level via :instance and children via association keys" do
        descriptor = HolderSerializer.new(only: {instance: [:foos], foos: [:name]}).descriptor

        expect(descriptor.attributes).to be_empty
        expect(descriptor.associations.map(&:name)).to eq(%i[foos])
        expect(descriptor.associations.first.descriptor.attributes.map(&:name)).to eq(%i[name])
      end

      it "shares the cached association element when it carries no sub-filter" do
        descriptor = HolderSerializer.new(only: [:foos]).descriptor

        expect(descriptor.associations.first).to equal(HolderSerializer.descriptor.associations.first)
      end
    end

    context "lazy resolution" do
      it "memoizes each level, so repeated reads return the same frozen array" do
        descriptor = FooSerializer.new(only: [:name]).descriptor

        expect(descriptor.attributes).to equal(descriptor.attributes)
      end
    end
  end

  context "filter parity with serialized output" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
          t.references :foos_holder
        end

        belongs_to :foos_holder, optional: true
      end

      Temping.create(:foos_holder) do
        with_columns do |t|
          t.string :name
        end

        has_many :foos
      end
    end

    let(:foo_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :address
      end
    end

    let(:holder_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name

        has_many :foos, serializer: FooSerializer
      end
    end

    before do
      stub_const("FooSerializer", foo_serializer_class)
      stub_const("HolderSerializer", holder_serializer_class)
    end

    it "exposes exactly the fields a filtered serialize emits, at every level" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo])

      serializer = HolderSerializer.new(only: {instance: [:name, :foos], foos: [:name]})
      output = serializer.serialize(holder)
      descriptor = serializer.descriptor

      root_fields = descriptor.attributes + descriptor.method_attributes + descriptor.associations
      expect(root_fields.map { |field| field.name.to_s }).to match_array(output.keys)

      nested = descriptor.associations.first.descriptor
      nested_fields = nested.attributes + nested.method_attributes + nested.associations
      expect(nested_fields.map { |field| field.name.to_s }).to match_array(output["foos"].first.keys)
    end
  end

  context "array serializer descriptor" do
    let(:foo_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :address
      end
    end

    before { stub_const("FooSerializer", foo_serializer_class) }

    it "returns the each_serializer's cached view when unfiltered" do
      array_serializer = Panko::ArraySerializer.new([], each_serializer: FooSerializer)

      expect(array_serializer.descriptor).to equal(FooSerializer.descriptor)
    end

    it "returns the each_serializer's filtered view when filtered" do
      array_serializer = Panko::ArraySerializer.new([], each_serializer: FooSerializer, only: [:name])

      expect(array_serializer.descriptor.attributes.map(&:name)).to eq(%i[name])
    end
  end
end
