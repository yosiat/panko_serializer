# frozen_string_literal: true

require "spec_helper"
require "active_record/connection_adapters/postgresql_adapter"

describe "Context and Scope" do
  context "context" do
    it "passes context to attribute methods" do
      class FooWithContextSerializer < Panko::Serializer
        attributes :name, :context_value

        def context_value
          context[:value]
        end
      end

      context = {value: Faker::Lorem.word}
      serializer_factory = -> { FooWithContextSerializer.new(context: context) }
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(serializer_factory,
        "name" => foo.name,
        "context_value" => context[:value])
    end
  end

  context "scope" do
    class FooWithScopeSerializer < Panko::Serializer
      attributes :scope_value

      def scope_value
        scope
      end
    end

    class FooHolderWithScopeSerializer < Panko::Serializer
      attributes :scope_value

      has_one :foo, serializer: FooWithScopeSerializer

      def scope_value
        scope
      end
    end

    it "passes scope to attribute methods" do
      scope = 123
      serializer_factory = -> { FooHolderWithScopeSerializer.new(scope: scope) }

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(serializer_factory,
        "scope_value" => scope,
        "foo" => {
          "scope_value" => scope
        })
    end

    it "default scope is nil" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo_holder = FooHolder.create(name: Faker::Lorem.word, foo: foo).reload

      expect(foo_holder).to serialized_as(FooHolderWithScopeSerializer, "scope_value" => nil,
        "foo" => {
          "scope_value" => nil
        })
    end
  end
end
