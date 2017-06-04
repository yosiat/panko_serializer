require "spec_helper"

RSpec.describe Panko::Serializer do
  Foo = Struct.new(:name, :address, :data)
  FoosHolder = Struct.new(:name, :foos)

  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  context "attributes" do
    it "instance variables" do
      serializer = FooSerializer.new
      foo = Foo.new(Faker::Lorem.word, Faker::Lorem.word)

      output = serializer.serialize foo

      expect(output).to eq({
        "name" => foo.name,
        "address" => foo.address
      })
    end

    it "method attributes" do
      class FooWithMethodsSerializer < Panko::Serializer
        attributes :name, :address, :something

        def something
          "#{object.name} #{object.address}"
        end
      end

      serializer = FooWithMethodsSerializer.new

      foo = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      output = serializer.serialize foo

      expect(output).to eq({
        "name" => foo.name,
        "address" => foo.address,
        "something" => "#{foo.name} #{foo.address}"
      })
    end
  end

  context "context" do
    it "passes context to attribute methods" do
      class FooWithContextSerializer < Panko::Serializer
        attributes :name, :context_value

        def context_value
          context[:value]
        end
      end

      context = { value: Faker::Lorem.word }
      serializer = FooWithContextSerializer.new(context: context)
      foo = Foo.new(Faker::Lorem.word, Faker::Lorem.word)

      output = serializer.serialize foo

      expect(output).to eq({
        "name" => foo.name,
        "context_value" => context[:value]
      })
    end
  end

  context "filter" do
    it "only" do
      serializer = FooSerializer.new(only: [:name])
      foo = Foo.new(Faker::Lorem.word, Faker::Lorem.word)

      output = serializer.serialize foo

      expect(output).to eq({
        "name" => foo.name
      })
    end

    it "except" do
      serializer = FooSerializer.new(except: [:name])
      foo = Foo.new(Faker::Lorem.word, Faker::Lorem.word)

      output = serializer.serialize foo

      expect(output).to eq({
        "address" => foo.address
      })
    end
  end

  context "has_one" do
    it "serializes using the given serializer", focus: true do
      FooHolder = Struct.new(:name, :foo)

      class FooHolderHasOneSerializer < Panko::Serializer
        attributes :name

        has_one :foo, serializer: FooSerializer
      end

      serializer = FooHolderHasOneSerializer.new

      foo = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo_holder = FooHolder.new(Faker::Lorem.word, foo)

      output = serializer.serialize foo_holder

      expect(output).to eq({
        "name" => foo_holder.name,
        "foo" => {
          "name" => foo.name,
          "address" => foo.address,
        }
      })
    end
  end

  context "has_many" do
    it "serializes using the given serializer" do
      class FoosHasManyHolderSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      serializer = FoosHasManyHolderSerializer.new

      foo1 = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo2 = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo_holder = FoosHolder.new(Faker::Lorem.word, [foo1, foo2])

      output = serializer.serialize foo_holder

      expect(output).to eq({
        "name" => foo_holder.name,
        "foos" => [
          {
            "name" => foo1.name,
            "address" => foo1.address,
          },
          {
            "name" => foo2.name,
            "address" => foo2.address,
          }
        ]
      })
    end

    it 'accepts only as option' do
      class FoosHolderWithOnlySerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer, only: [:address]
      end

      serializer = FoosHolderWithOnlySerializer.new

      foo1 = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo2 = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo_holder = FoosHolder.new(Faker::Lorem.word, [foo1, foo2])

      output = serializer.serialize foo_holder

      expect(output).to eq({
        'name' => foo_holder.name,
        'foos' => [
          {
            'address' => foo1.address
          },
          {
            'address' => foo2.address
          }
        ]
      })
    end

    it "filters associations" do
      class FoosHolderForFilterTestSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      serializer = FoosHolderForFilterTestSerializer.new only: [:foos]

      foo1 = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo2 = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo_holder = FoosHolder.new(Faker::Lorem.word, [foo1, foo2])

      output = serializer.serialize foo_holder


      expect(output).to eq({
        "foos" => [
          {
            "name" => foo1.name,
            "address" => foo1.address
          },
          {
            "name" => foo2.name,
            "address" => foo2.address
          }
        ]
      })
    end
  end

  context 'filters' do
    it 'support nested "only" filter' do

      class FoosHolderSerializer < Panko::Serializer
        attributes :name
        has_many :foos, serializer: FooSerializer
      end

      serializer = FoosHolderSerializer.new only: { foos: [:address] }

      foo1 = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo2 = Foo.new(Faker::Lorem.word, Faker::Lorem.word)
      foo_holder = FoosHolder.new(Faker::Lorem.word, [foo1, foo2])

      output = serializer.serialize foo_holder

      expect(output).to eq({
        'name' => foo_holder.name,
        'foos' => [
          {
            'address' => foo1.address,
          },
          {
            'address' => foo2.address,
          }
        ]
      })
    end
  end
end
