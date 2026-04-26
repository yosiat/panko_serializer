# frozen_string_literal: true

require "serializers_code_gen"

RSpec.describe SerializersCodeGen::Validators::SourceResolution do
  let(:config) { SerializersCodeGen::Config.new }

  # Minimal AR-like fake: anything responding to +#columns_hash+,
  # +#method_defined?+, +#attribute_methods_generated?+, and
  # +#define_attribute_methods+. Mirrors the duck-type the validator
  # relies on so unit coverage runs without booting a real ActiveRecord
  # stack — same fixture pattern S4.1 uses for +callable_arity_spec.rb+.
  def fake_ar_class(name:, columns: [], methods: [])
    columns_arr = columns
    methods_arr = methods
    Class.new do
      define_singleton_method(:name) { name }
      define_singleton_method(:columns_hash) { columns_arr.to_h { |c| [c, :stub] } }
      define_singleton_method(:method_defined?) { |sym| methods_arr.include?(sym.to_sym) }
      define_singleton_method(:attribute_methods_generated?) { true }
      define_singleton_method(:define_attribute_methods) { nil }
    end
  end

  def descriptor_with(name: "PostDescriptor", models: nil, attributes: [], associations: [])
    SerializersCodeGen::Descriptor.new(
      name: name,
      models: models,
      attributes: attributes,
      method_attributes: [],
      associations: associations
    )
  end

  def attribute(name, source: name)
    SerializersCodeGen::Attribute.new(name: name, source: source)
  end

  describe ".validate — column outcome" do
    it "passes when source is a column on the single Model" do
      klass = fake_ar_class(name: "Post", columns: ["title"])
      descriptor = descriptor_with(models: [klass], attributes: [attribute(:title)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end

    it "passes when source defaults from name and the name is a column" do
      klass = fake_ar_class(name: "Post", columns: ["id", "title"])
      descriptor = descriptor_with(
        models: [klass],
        attributes: [attribute(:id), attribute(:title)]
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end
  end

  describe ".validate — method outcome" do
    it "passes when source is an instance method on the single Model" do
      klass = fake_ar_class(name: "Post", columns: ["id"], methods: %i[full_title])
      descriptor = descriptor_with(models: [klass], attributes: [attribute(:full_title)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end
  end

  describe ".validate — UnknownSourceError" do
    it "raises when source is neither a column nor an instance method" do
      klass = fake_ar_class(name: "Post", columns: ["id"], methods: %i[full_title])
      descriptor = descriptor_with(models: [klass], attributes: [attribute(:missing)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::UnknownSourceError,
        "PostDescriptor#missing: Attribute#source :missing is not a column or instance method on Post."
      )
    end

    it "names the resolved source (not the Field name) when source differs from name" do
      klass = fake_ar_class(name: "Post", columns: ["id"])
      descriptor = descriptor_with(
        models: [klass],
        attributes: [attribute(:title, source: :raw_title)]
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::UnknownSourceError,
        "PostDescriptor#title: Attribute#source :raw_title is not a column or instance method on Post."
      )
    end
  end

  describe ".validate — Models: nil" do
    it "does not raise when models is nil (Generic path; defers to runtime NoMethodError)" do
      descriptor = descriptor_with(
        models: nil,
        attributes: [attribute(:title), attribute(:anything)]
      )
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end
  end

  describe ".validate — non-AR class in models:" do
    it "skips classification for a plain Class.new (no +columns_hash+) and does not raise" do
      non_ar = Class.new do
        def self.name = "PlainClass"
      end
      descriptor = descriptor_with(models: [non_ar], attributes: [attribute(:anything)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end
  end

  describe ".validate — multi-class intersection (S7.1)" do
    it "passes when source is column-backed on every class in models:" do
      v = fake_ar_class(name: "Vehicle", columns: ["vin", "make"])
      c = fake_ar_class(name: "Car", columns: ["vin", "make"])
      descriptor = descriptor_with(models: [v, c], attributes: [attribute(:vin)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end

    it "passes when source is uniformly an instance method on every class (uniform method)" do
      v = fake_ar_class(name: "Vehicle", columns: ["id"], methods: %i[label])
      c = fake_ar_class(name: "Car", columns: ["id"], methods: %i[label])
      descriptor = descriptor_with(models: [v, c], attributes: [attribute(:label)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end

    it "passes when one class lacks the column (downgrade — column-backed on one, method-only on the other)" do
      v = fake_ar_class(name: "Vehicle", columns: ["make"], methods: %i[make])
      c = fake_ar_class(name: "Car", columns: [], methods: %i[make])
      descriptor = descriptor_with(models: [v, c], attributes: [attribute(:make)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end

    it "raises UnknownSourceError when source is missing on at least one class; message names the class" do
      v = fake_ar_class(name: "Vehicle", columns: ["vin"], methods: %i[wheels])
      c = fake_ar_class(name: "Car", columns: ["vin"])
      descriptor = descriptor_with(models: [v, c], attributes: [attribute(:wheels)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::UnknownSourceError,
        "PostDescriptor#wheels: Attribute#source :wheels is not a column or instance method on Car."
      )
    end

    it "names every missing class when the source is absent from multiple classes" do
      v = fake_ar_class(name: "Vehicle", columns: ["vin"])
      c = fake_ar_class(name: "Car", columns: ["vin"])
      t = fake_ar_class(name: "Truck", columns: ["vin"])
      descriptor = descriptor_with(models: [v, c, t], attributes: [attribute(:wheels)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::UnknownSourceError,
        "PostDescriptor#wheels: Attribute#source :wheels is not a column or instance method on Vehicle, Car, Truck."
      )
    end

    it "calls DefineAttributeMethods.ensure! once per AR class in models: before any classification" do
      define_calls = Hash.new(0)
      generated = Hash.new(false)
      build = ->(name) {
        Class.new do
          define_singleton_method(:name) { name }
          define_singleton_method(:columns_hash) { {"vin" => :stub} }
          define_singleton_method(:method_defined?) { |_| false }
          define_singleton_method(:attribute_methods_generated?) { generated[name] }
          define_singleton_method(:define_attribute_methods) do
            define_calls[name] += 1
            generated[name] = true
          end
        end
      }
      v = build.call("Vehicle")
      c = build.call("Car")
      descriptor = descriptor_with(models: [v, c], attributes: [attribute(:vin)])
      described_class.validate(descriptor, output: :json, config: config)
      expect(define_calls).to eq({"Vehicle" => 1, "Car" => 1})
    end

    it "skips classification when models: contains only non-AR classes" do
      non_ar1 = Class.new { def self.name = "PlainOne" }
      non_ar2 = Class.new { def self.name = "PlainTwo" }
      descriptor = descriptor_with(models: [non_ar1, non_ar2], attributes: [attribute(:anything)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end

    it "filters non-AR classes from models: and classifies against the AR-class subset only" do
      non_ar = Class.new { def self.name = "PlainClass" }
      ar = fake_ar_class(name: "Post", columns: ["title"])
      descriptor = descriptor_with(models: [non_ar, ar], attributes: [attribute(:title)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.not_to raise_error
    end

    it "does not name a non-AR class in the error message when only the AR class is missing the source" do
      non_ar = Class.new { def self.name = "PlainClass" }
      ar = fake_ar_class(name: "Post", columns: ["id"])
      descriptor = descriptor_with(models: [non_ar, ar], attributes: [attribute(:title)])
      expect {
        described_class.validate(descriptor, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::UnknownSourceError,
        "PostDescriptor#title: Attribute#source :title is not a column or instance method on Post."
      )
    end
  end

  describe ".validate — DefineAttributeMethods.ensure! is invoked per AR class" do
    it "calls #define_attribute_methods on the model when its readers haven't been generated yet" do
      define_calls = 0
      generated = false
      klass = Class.new do
        define_singleton_method(:name) { "Post" }
        define_singleton_method(:columns_hash) { {"title" => :stub} }
        define_singleton_method(:method_defined?) { |_| false }
        define_singleton_method(:attribute_methods_generated?) { generated }
        define_singleton_method(:define_attribute_methods) do
          define_calls += 1
          generated = true
        end
      end
      descriptor = descriptor_with(models: [klass], attributes: [attribute(:title)])
      described_class.validate(descriptor, output: :json, config: config)
      expect(define_calls).to eq(1)
    end
  end

  describe ".validate — nested Descriptor walk" do
    it "raises when a nested Descriptor has an unresolved Source" do
      inner_klass = fake_ar_class(name: "Author", columns: ["id"])
      inner = SerializersCodeGen::Descriptor.new(
        name: "AuthorDescriptor",
        models: [inner_klass],
        attributes: [attribute(:missing)],
        method_attributes: [],
        associations: []
      )
      assoc = SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: inner)
      outer = descriptor_with(associations: [assoc])
      expect {
        described_class.validate(outer, output: :json, config: config)
      }.to raise_error(
        SerializersCodeGen::UnknownSourceError,
        "AuthorDescriptor#missing: Attribute#source :missing is not a column or instance method on Author."
      )
    end
  end

  describe ".validate — cycle / shared-subtree handling" do
    it "validates a shared inner Descriptor referenced from two Associations without re-walking" do
      inner_klass = fake_ar_class(name: "Author", columns: ["id"])
      inner = SerializersCodeGen::Descriptor.new(
        name: "AuthorDescriptor",
        models: [inner_klass],
        attributes: [attribute(:id)],
        method_attributes: [],
        associations: []
      )
      assoc1 = SerializersCodeGen::Association.new(name: :a, kind: :has_one, descriptor: inner)
      assoc2 = SerializersCodeGen::Association.new(name: :b, kind: :has_one, descriptor: inner)
      outer = descriptor_with(associations: [assoc1, assoc2])
      expect {
        described_class.validate(outer, output: :json, config: config)
      }.not_to raise_error
    end

    it "does not infinite-loop on a self-referencing Descriptor" do
      parent_klass = fake_ar_class(name: "Comment", columns: ["id", "body"])
      parent = SerializersCodeGen::Descriptor.new(
        name: "CommentDescriptor",
        models: [parent_klass],
        attributes: [attribute(:body)],
        method_attributes: [],
        associations: []
      )
      parent.associations << SerializersCodeGen::Association.new(
        name: :replies, kind: :has_many, descriptor: parent
      )
      expect {
        described_class.validate(parent, output: :json, config: config)
      }.not_to raise_error
    end
  end

  describe ".validate — no Generated Class produced on raise" do
    it "raises before SerializersCodeGen.compile emits any source" do
      klass = fake_ar_class(name: "Post", columns: ["id"])
      bad = descriptor_with(models: [klass], attributes: [attribute(:bad)])
      generated_class = nil
      expect {
        generated_class = SerializersCodeGen.compile(bad, output: :json, config: config)
      }.to raise_error(SerializersCodeGen::UnknownSourceError)
      expect(generated_class).to be_nil
    end
  end

  describe "registration in the Validator orchestrator" do
    it "is included in Validator::DEFAULT_RULES" do
      expect(SerializersCodeGen::Validators::Validator::DEFAULT_RULES)
        .to include(described_class)
    end

    it "is registered immediately after CallableArity" do
      rules = SerializersCodeGen::Validators::Validator::DEFAULT_RULES
      arity_index = rules.index(SerializersCodeGen::Validators::CallableArity)
      source_index = rules.index(described_class)
      expect(source_index).to eq(arity_index + 1)
    end

    it "is invoked by the orchestrator on Compile" do
      klass = fake_ar_class(name: "Post", columns: ["id"])
      bad = descriptor_with(models: [klass], attributes: [attribute(:missing)])
      expect {
        SerializersCodeGen::Validators::Validator.new.validate(bad, output: :json, config: config)
      }.to raise_error(SerializersCodeGen::UnknownSourceError, /not a column or instance method on Post/)
    end
  end
end
