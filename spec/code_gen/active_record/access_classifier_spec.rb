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
      expect(described_class.classify(klass, :title)).to eq(:column)
    end

    it "returns :column when columns_hash key matches a String source" do
      klass = fake_ar_class(name: "Post", columns: ["title"])
      expect(described_class.classify(klass, "title")).to eq(:column)
    end

    it "returns :method when source is not a column but is an instance method" do
      klass = fake_ar_class(name: "Post", columns: ["id"], methods: %i[full_title])
      expect(described_class.classify(klass, :full_title)).to eq(:method)
    end

    it "prefers :column over :method when source is both a column and a method (override bypassed)" do
      klass = fake_ar_class(name: "Post", columns: ["title"], methods: %i[title])
      expect(described_class.classify(klass, :title)).to eq(:column)
    end

    it "raises UnknownSourceError when source is neither a column nor an instance method" do
      klass = fake_ar_class(name: "Post", columns: ["id"], methods: %i[full_title])
      expect {
        described_class.classify(klass, :missing)
      }.to raise_error(SerializersCodeGen::UnknownSourceError)
    end

    it "names the class and source in the raised message" do
      klass = fake_ar_class(name: "Post", columns: ["id"], methods: [])
      expect {
        described_class.classify(klass, :missing)
      }.to raise_error(SerializersCodeGen::UnknownSourceError, /Post/) { |err|
        expect(err.message).to include(":missing")
      }
    end
  end
end
