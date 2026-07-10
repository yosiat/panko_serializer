# frozen_string_literal: true

require "spec_helper"

describe "Serializer instance pooling" do
  let(:name) { "Jane Doe" }
  let(:address) { "1 Infinite Loop" }
  let(:other_name) { "John Smith" }
  let(:foo) { Foo.create(name: name, address: address).reload }
  let(:other_foo) { Foo.create(name: other_name, address: address).reload }

  before do
    Temping.create(:foo) do
      with_columns do |t|
        t.string :name
        t.string :address
      end
    end
  end

  let(:serializer_class) do
    stub_const("PooledFooSerializer", Class.new(Panko::Serializer) do
      attributes :name, :address
    end)
  end

  def pooled_stack(klass)
    klass._cg_pool_json.stack
  end

  it "reuses one generated instance across sequential serializes on a thread" do
    serializer_class.new.serialize_to_json(foo)
    first_pooled = pooled_stack(serializer_class).last

    serializer_class.new.serialize_to_json(foo)

    expect(pooled_stack(serializer_class).last).to be(first_pooled)
    expect(pooled_stack(serializer_class).size).to eq(1)
  end

  it "releases per-record state at checkin — a pooled instance holds no record" do
    stub_const("PooledMethodFooSerializer", Class.new(Panko::Serializer) do
      attributes :name, :shouted_name

      def shouted_name
        object.name.upcase
      end
    end)

    PooledMethodFooSerializer.new.serialize_to_json(foo)

    expect(PooledMethodFooSerializer._cg_pool_json.stack.last.object).to be_nil
  end

  it "builds a second instance for a reentrant serialize instead of corrupting the first" do
    reentrant_output = nil
    stub_const("ReentrantFooSerializer", Class.new(Panko::Serializer) do
      attributes :name, :nested

      define_method(:nested) do
        # Reenters the same serializer class and mode mid-emit — pre-pooling
        # this got a fresh instance; the pool must preserve that isolation.
        reentrant_output = Oj.load(ReentrantFooSerializer.new(except: [:nested]).serialize_to_json(object))
        object.name
      end
    end)

    result = Oj.load(ReentrantFooSerializer.new.serialize_to_json(foo))

    expect(result).to eq("name" => name, "nested" => name)
    expect(reentrant_output).to eq("name" => name)
    expect(ReentrantFooSerializer._cg_pool_json.stack.size).to eq(2)
  end

  it "returns the instance to the pool when serialization raises" do
    stub_const("RaisingFooSerializer", Class.new(Panko::Serializer) do
      attributes :name, :boom

      def boom
        raise "mid-serialize failure"
      end
    end)

    expect { RaisingFooSerializer.new.serialize_to_json(foo) }.to raise_error(RuntimeError, /mid-serialize/)

    expect(RaisingFooSerializer._cg_pool_json.stack.size).to eq(1)
    recovered = Oj.load(RaisingFooSerializer.new(except: [:boom]).serialize_to_json(foo))
    expect(recovered).to eq("name" => name)
  end

  it "honors a filters_for defined after the class has already serialized" do
    unfiltered = Oj.load(serializer_class.new.serialize_to_json(foo))
    expect(unfiltered).to eq("name" => name, "address" => address)

    def serializer_class.filters_for(_context, _scope)
      {only: [:name]}
    end

    filtered = Oj.load(serializer_class.new.serialize_to_json(other_foo))
    expect(filtered).to eq("name" => other_name)
  end
end
