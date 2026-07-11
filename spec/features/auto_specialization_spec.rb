# frozen_string_literal: true

require "spec_helper"
require "stringio"

describe "Auto-specialization" do
  let(:name) { "Jane Doe" }
  let(:address) { "1 Infinite Loop" }
  let(:foo) { Foo.create(name: name, address: address).reload }
  let(:hash_record) { {"name" => name, "address" => address} }
  let(:expected) { {"name" => name, "address" => address} }

  before do
    Temping.create(:foo) do
      with_columns do |t|
        t.string :name
        t.string :address
      end
    end
  end

  around do |example|
    original_capacity = Panko::Config.auto_specialization.capacity
    original_enabled = Panko::Config.auto_specialization.enabled
    example.run
  ensure
    Panko::Config.auto_specialization.capacity = original_capacity
    Panko::Config.auto_specialization.enabled = original_enabled
  end

  let(:serializer_class) do
    stub_const("AutoFooSerializer", Class.new(Panko::Serializer) do
      attributes :name, :address
    end)
  end

  def variant_pool_for(klass, mode, model)
    Panko::CodeGen::SerializerCache.variant_pool(klass, mode, model)
  end

  describe "dispatch by record class" do
    it "compiles a specialized variant for an AR record class on first sight" do
      serializer_class.new.serialize_to_json(foo)

      variant = serializer_class._cg_variants_json.fetch(Foo)
      expect(variant).not_to be(serializer_class._cg_pool_json)
    end

    it "pins a Hash record class to the base generic pool" do
      serializer_class.new.serialize_to_json(hash_record)

      expect(serializer_class._cg_variants_json.fetch(Hash)).to be(serializer_class._cg_pool_json)
    end

    it "pins an anonymous AR class to the base generic pool (guard needs a constant path)" do
      anonymous_model = Class.new(ActiveRecord::Base) { self.table_name = "foos" }
      record = anonymous_model.create(name: name, address: address).reload

      expect(Oj.load(serializer_class.new.serialize_to_json(record))).to eq(expected)
      expect(serializer_class._cg_variants_json.fetch(anonymous_model)).to be(serializer_class._cg_pool_json)
    end

    it "pins to generic when the specialized compile fails, deferring to the runtime error" do
      invalid = stub_const("InvalidFooSerializer", Class.new(Panko::Serializer) do
        attributes :name, :not_a_column
      end)

      expect { invalid.new.serialize_to_json(foo) }.to raise_error(NoMethodError, /not_a_column/)
      expect(invalid._cg_variants_json.fetch(Foo)).to be(invalid._cg_pool_json)
    end

    it "routes every record class to the generic pool when disabled" do
      Panko::Config.auto_specialization.enabled = false

      serializer_class.new.serialize_to_json(foo)

      expect(serializer_class._cg_variants_json.fetch(Foo)).to be(serializer_class._cg_pool_json)
    end
  end

  describe "output parity with the generic path" do
    def generic_output(mode, record)
      Panko::Config.auto_specialization.enabled = false
      generic_class = stub_const("GenericTwinFooSerializer", Class.new(Panko::Serializer) do
        attributes :name, :address
      end)
      output = (mode == :json) ? generic_class.new.serialize_to_json(record) : generic_class.new.serialize(record)
      Panko::Config.auto_specialization.enabled = true
      output
    end

    it "serializes an AR record byte-identically to the generic path (json)" do
      expect(serializer_class.new.serialize_to_json(foo)).to eq(generic_output(:json, foo))
    end

    it "serializes an AR record identically to the generic path (hash)" do
      expect(serializer_class.new.serialize(foo)).to eq(generic_output(:hash, foo))
    end

    it "serializes a Hash record unchanged" do
      expect(Oj.load(serializer_class.new.serialize_to_json(hash_record))).to eq(expected)
      expect(serializer_class.new.serialize(hash_record)).to eq(expected)
    end

    it "honors a user-defined reader override on the specialized variant" do
      shouting = stub_const("ShoutingFooSerializer", Class.new(Panko::Serializer) do
        attributes :name, :address
      end)
      Foo.class_eval do
        def name
          super.upcase
        end
      end

      expect(Oj.load(shouting.new.serialize_to_json(foo))).to eq(
        "name" => name.upcase, "address" => address
      )
    end

    it "supports method attributes reading object and context on the specialized variant" do
      method_serializer = stub_const("MethodFooSerializer", Class.new(Panko::Serializer) do
        attributes :name, :labeled

        def labeled
          "#{object.name} (#{context})"
        end
      end)

      output = Oj.load(method_serializer.new(context: "ctx").serialize_to_json(foo))
      expect(output).to eq("name" => name, "labeled" => "#{name} (ctx)")
    end

    it "applies only/except filters on the specialized variant" do
      expect(Oj.load(serializer_class.new(only: [:name]).serialize_to_json(foo))).to eq("name" => name)
      expect(Oj.load(serializer_class.new(except: [:name]).serialize_to_json(foo))).to eq("address" => address)
    end
  end

  describe "arrays" do
    it "serializes a homogeneous AR array through the specialized variant" do
      records = [foo, Foo.create(name: name, address: address).reload]
      json = Panko::ArraySerializer.new(records, each_serializer: serializer_class).to_json

      expect(Oj.load(json).size).to eq(records.size)
      expect(serializer_class._cg_variants_json.fetch(Foo)).not_to be(serializer_class._cg_pool_json)
    end

    it "serializes an empty array" do
      json = Panko::ArraySerializer.new([], each_serializer: serializer_class).to_json
      expect(json).to eq("[]")
    end

    it "serializes a heterogeneous array — mismatched records take the guarded generic fallback" do
      json = Panko::ArraySerializer.new([foo, hash_record], each_serializer: serializer_class).to_json

      expect(Oj.load(json)).to eq([expected, expected])
    end
  end

  describe "capacity" do
    let(:capacity_of_one) { 1 }

    it "pins record classes past capacity to the generic pool and keeps output correct" do
      Panko::Config.auto_specialization.capacity = capacity_of_one
      second_model = Class.new(ActiveRecord::Base) { self.table_name = "foos" }
      stub_const("SecondFoo", second_model)
      second_record = SecondFoo.create(name: name, address: address).reload

      first_output = nil
      second_output = nil
      silence_warnings_to_stderr do
        first_output = Oj.load(serializer_class.new.serialize_to_json(foo))
        second_output = Oj.load(serializer_class.new.serialize_to_json(second_record))
      end

      expect(first_output).to eq(expected)
      expect(second_output).to eq(expected)
      expect(serializer_class._cg_variants_json.fetch(Foo)).not_to be(serializer_class._cg_pool_json)
      expect(serializer_class._cg_variants_json.fetch(SecondFoo)).to be(serializer_class._cg_pool_json)
    end

    it "warns exactly once per serializer class when capacity is reached" do
      Panko::Config.auto_specialization.capacity = capacity_of_one
      stub_const("SecondFoo", Class.new(ActiveRecord::Base) { self.table_name = "foos" })
      stub_const("ThirdFoo", Class.new(ActiveRecord::Base) { self.table_name = "foos" })
      second_record = SecondFoo.create(name: name, address: address).reload
      third_record = ThirdFoo.create(name: name, address: address).reload

      warnings = capture_warnings do
        serializer_class.new.serialize_to_json(foo)
        serializer_class.new.serialize_to_json(second_record)
        serializer_class.new.serialize_to_json(third_record)
      end

      expect(warnings.size).to eq(1)
      expect(warnings.first).to include("auto-specialization capacity (#{capacity_of_one}) reached")
      expect(warnings.first).to include("Panko::Config.auto_specialization.capacity")
    end
  end

  describe "instance pooling on variants" do
    it "reuses one variant instance across sequential serializes" do
      serializer_class.new.serialize_to_json(foo)
      stack = variant_pool_for(serializer_class, :json, Foo).stack
      first_pooled = stack.last

      serializer_class.new.serialize_to_json(foo)

      expect(stack.last).to be(first_pooled)
      expect(stack.size).to eq(1)
    end
  end

  def silence_warnings_to_stderr(&block)
    capture_warnings(&block)
    nil
  end

  def capture_warnings
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string.lines.map(&:chomp)
  ensure
    $stderr = original_stderr
  end
end
