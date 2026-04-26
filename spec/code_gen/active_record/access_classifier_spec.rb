# frozen_string_literal: true

require "serializers_code_gen"

RSpec.describe SerializersCodeGen::ActiveRecord::AccessClassifier do
  # A minimal AR-like fake: anything responding to +#columns_hash+ +
  # +#method_defined?+. Mirrors the duck-type the classifier relies on
  # so unit coverage runs without booting a real ActiveRecord stack.
  def fake_ar_class(name:, columns: [], methods: [])
    Class.new do
      define_singleton_method(:name) { name }
      define_singleton_method(:columns_hash) { columns.to_h { |c| [c, :stub] } }
      define_singleton_method(:method_defined?) { |sym| methods.include?(sym.to_sym) }
    end
  end

  describe ".classify" do
    it "returns :column when source is in columns_hash" do
      klass = fake_ar_class(name: "Post", columns: ["title", "id"])
      expect(described_class.classify([klass], :title)).to eq(:column)
    end

    it "returns :column when columns_hash key matches a String source" do
      klass = fake_ar_class(name: "Post", columns: ["title"])
      expect(described_class.classify([klass], "title")).to eq(:column)
    end

    it "returns :method when source is not a column but is an instance method" do
      klass = fake_ar_class(name: "Post", columns: ["id"], methods: %i[full_title])
      expect(described_class.classify([klass], :full_title)).to eq(:method)
    end

    it "prefers :column over :method when source is both a column and a method (override bypassed)" do
      klass = fake_ar_class(name: "Post", columns: ["title"], methods: %i[title])
      expect(described_class.classify([klass], :title)).to eq(:column)
    end

    it "raises UnknownSourceError when source is neither a column nor an instance method" do
      klass = fake_ar_class(name: "Post", columns: ["id"], methods: %i[full_title])
      expect {
        described_class.classify([klass], :missing)
      }.to raise_error(SerializersCodeGen::UnknownSourceError)
    end

    it "names the class and source in the raised message" do
      klass = fake_ar_class(name: "Post", columns: ["id"], methods: [])
      expect {
        described_class.classify([klass], :missing)
      }.to raise_error(SerializersCodeGen::UnknownSourceError, /Post/) { |err|
        expect(err.message).to include(":missing")
      }
    end

    describe "multi-class intersection (S7.1)" do
      # Per +docs/compilation.md § STI and mixed class sets+:
      #   1. column-in-all → :column
      #   2. else, method-in-all → :method (downgrade)
      #   3. else (some class has neither) → raise
      #
      # The fake's +method_defined?+ returns +true+ only for entries
      # listed in +methods:+. To model real-AR semantics where AR's
      # generated readers make +method_defined?+ true for every column,
      # tests that include the column also list it in +methods:+ when
      # the +method_defined?+ verdict matters for the rule.

      it "returns :column when source is column-backed on every class" do
        v = fake_ar_class(name: "Vehicle", columns: ["vin", "make"])
        c = fake_ar_class(name: "Car", columns: ["vin", "make"])
        expect(described_class.classify([v, c], :vin)).to eq(:column)
      end

      it "returns :method when source is an instance method on every class (uniform method)" do
        v = fake_ar_class(name: "Vehicle", columns: ["id"], methods: %i[label])
        c = fake_ar_class(name: "Car", columns: ["id"], methods: %i[label])
        expect(described_class.classify([v, c], :label)).to eq(:method)
      end

      it "downgrades to :method when one class lacks the column (column-backed on one, method-only on the other)" do
        v = fake_ar_class(name: "Vehicle", columns: ["make"], methods: %i[make])
        c = fake_ar_class(name: "Car", columns: [], methods: %i[make])
        expect(described_class.classify([v, c], :make)).to eq(:method)
      end

      it "raises UnknownSourceError when source is missing from at least one class" do
        v = fake_ar_class(name: "Vehicle", columns: ["vin"])
        c = fake_ar_class(name: "Car", columns: ["vin"], methods: %i[wheels])
        expect {
          described_class.classify([v, c], :wheels)
        }.to raise_error(SerializersCodeGen::UnknownSourceError)
      end

      it "names the offending class in the raised message when only one class lacks the source" do
        v = fake_ar_class(name: "Vehicle", columns: ["vin"], methods: %i[wheels])
        c = fake_ar_class(name: "Car", columns: ["vin"])
        expect {
          described_class.classify([v, c], :wheels)
        }.to raise_error(SerializersCodeGen::UnknownSourceError) { |err|
          expect(err.message).to include("Car")
          expect(err.message).to include(":wheels")
        }
      end

      it "treats a 1-element Array as the single-class case" do
        klass = fake_ar_class(name: "Post", columns: ["title"])
        expect(described_class.classify([klass], :title)).to eq(:column)
      end

      it "treats a 1-element Array as the single-class column-wins case (single-class override-bypass preserved)" do
        klass = fake_ar_class(name: "Post", columns: ["title"], methods: %i[title])
        expect(described_class.classify([klass], :title)).to eq(:column)
      end

      it "raises with all missing classes named when the source is absent on multiple classes" do
        v = fake_ar_class(name: "Vehicle", columns: ["vin"])
        c = fake_ar_class(name: "Car", columns: ["vin"])
        t = fake_ar_class(name: "Truck", columns: ["vin"])
        expect {
          described_class.classify([v, c, t], :wheels)
        }.to raise_error(SerializersCodeGen::UnknownSourceError) { |err|
          expect(err.message).to include("Vehicle")
          expect(err.message).to include("Car")
          expect(err.message).to include("Truck")
        }
      end

      it "supports a 3-class uniform-column intersection" do
        v = fake_ar_class(name: "Vehicle", columns: ["vin"])
        c = fake_ar_class(name: "Car", columns: ["vin"])
        t = fake_ar_class(name: "Truck", columns: ["vin"])
        expect(described_class.classify([v, c, t], :vin)).to eq(:column)
      end
    end
  end
end
