# frozen_string_literal: true

require "spec_helper"

describe "Context and Scope" do
  context "context" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end
    end

    it "passes context to attribute methods" do
      class FooWithContextSerializer < Panko::Serializer
        attributes :name, :context_value

        def context_value
          context[:value]
        end
      end

      context = {value: Faker::Lorem.word}
      serializer_factory = -> { FooWithContextSerializer.new(context: context) }
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(serializer_factory,
        "name" => foo.name,
        "context_value" => context[:value])
    end
  end

  context "scope" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end

      Temping.create(:foo_holder) do
        with_columns do |t|
          t.string :name
          t.references :foo
        end

        belongs_to :foo
      end
    end

    let(:foo_with_scope_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :scope_value

        def scope_value
          scope
        end
      end
    end

    let(:foo_holder_with_scope_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :scope_value

        has_one :foo, serializer: "FooWithScopeSerializer"

        def scope_value
          scope
        end
      end
    end

    before do
      stub_const("FooWithScopeSerializer", foo_with_scope_serializer_class)
      stub_const("FooHolderWithScopeSerializer", foo_holder_with_scope_serializer_class)
    end

    it "passes scope to attribute methods" do
      scope = 123
      serializer_factory = -> { FooHolderWithScopeSerializer.new(scope: scope) }

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo)

      expect(foo_holder).to serialized_as(serializer_factory,
        "scope_value" => scope,
        "foo" => {
          "scope_value" => scope
        })
    end

    it "default scope is nil" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo)

      expect(foo_holder).to serialized_as(FooHolderWithScopeSerializer, "scope_value" => nil,
        "foo" => {
          "scope_value" => nil
        })
    end
  end
end
