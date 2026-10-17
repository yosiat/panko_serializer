# frozen_string_literal: true

require "panko/code_gen"

RSpec.describe Panko::CodeGen::ActiveRecord::AccessClassifier do
  # +method_owners+ maps a reader to +:ar_generated+ (AR's generated attribute module) or +:user_class+ (a user override).
  def fake_ar_class(name:, columns: [], method_owners: {})
    Class.new do
      ar_gen_module = Module.new do
        singleton_class.define_method(:name) { "#{name}::GeneratedAttributeMethods" }
        singleton_class.define_method(:to_s) { "#{name}::GeneratedAttributeMethods" }
      end
      define_singleton_method(:name) { name }
      define_singleton_method(:to_s) { name }
      define_singleton_method(:columns_hash) { columns.to_h { |c| [c, :stub] } }
      define_singleton_method(:method_defined?) { |sym| method_owners.key?(sym.to_sym) }
      define_singleton_method(:instance_method) { |sym|
        owner_kind = method_owners.fetch(sym.to_sym)
        actual_owner = (owner_kind == :ar_generated) ? ar_gen_module : self
        stub = Object.new
        stub.define_singleton_method(:owner) { actual_owner }
        stub
      }
    end
  end

  describe ".classify" do
    it "returns :column when source is in columns_hash and the reader is AR's generated one" do
      klass = fake_ar_class(name: "Post", columns: ["title", "id"], method_owners: {title: :ar_generated})
      expect(described_class.classify(klass, :title)).to eq(:column)
    end

    it "returns :column when columns_hash key matches a String source" do
      klass = fake_ar_class(name: "Post", columns: ["title"], method_owners: {title: :ar_generated})
      expect(described_class.classify(klass, "title")).to eq(:column)
    end

    it "returns :column when the column has no reader defined yet (pre-define_attribute_methods)" do
      klass = fake_ar_class(name: "Post", columns: ["title"])
      expect(described_class.classify(klass, :title)).to eq(:column)
    end

    it "returns :method when source is not a column but is an instance method" do
      klass = fake_ar_class(name: "Post", columns: ["id"], method_owners: {full_title: :user_class})
      expect(described_class.classify(klass, :full_title)).to eq(:method)
    end

    it "returns :method for a column whose reader is user-overridden (override honored, not bypassed)" do
      klass = fake_ar_class(name: "Post", columns: ["title"], method_owners: {title: :user_class})
      expect(described_class.classify(klass, :title)).to eq(:method)
    end

    it "returns :method when the override comes from a mixed-in module rather than the class itself" do
      concern = Module.new { singleton_class.define_method(:name) { "TitleConcern" } }
      klass = fake_ar_class(name: "Post", columns: ["title"])
      klass.define_singleton_method(:method_defined?) { |sym| sym.to_sym == :title }
      klass.define_singleton_method(:instance_method) { |_sym|
        stub = Object.new
        stub.define_singleton_method(:owner) { concern }
        stub
      }
      expect(described_class.classify(klass, :title)).to eq(:method)
    end

    it "raises UnknownSourceError when source is neither a column nor an instance method" do
      klass = fake_ar_class(name: "Post", columns: ["id"], method_owners: {full_title: :user_class})
      expect {
        described_class.classify(klass, :missing)
      }.to raise_error(Panko::CodeGen::UnknownSourceError)
    end

    it "names the class and source in the raised message" do
      klass = fake_ar_class(name: "Post", columns: ["id"])
      expect {
        described_class.classify(klass, :missing)
      }.to raise_error(
        Panko::CodeGen::UnknownSourceError,
        "Post: source :missing is not a column or instance method."
      )
    end

    it "recognizes AR's generated reader on an anonymous model (nil-named GeneratedAttributeMethods)" do
      model = Class.new(::ActiveRecord::Base) { self.table_name = "posts" }
      model.define_attribute_methods
      expect(described_class.classify(model, :title)).to eq(:column)
    end
  end

  describe ".json_typed?" do
    it "returns true for a t.json column" do
      expect(described_class.json_typed?(Post, :metadata)).to be(true)
    end

    it "accepts the attribute name as a String as well as a Symbol" do
      expect(described_class.json_typed?(Post, "metadata")).to be(true)
    end

    it "returns false for a t.string column" do
      expect(described_class.json_typed?(Post, :title)).to be(false)
    end

    it "returns false for an integer column" do
      expect(described_class.json_typed?(Post, :views)).to be(false)
    end

    it "returns false for an unknown attribute name (Type::Value fallback)" do
      expect(described_class.json_typed?(Post, :does_not_exist)).to be(false)
    end

    it "accepts a custom subclass of ActiveRecord::Type::Json (is_a, not exact match)" do
      stub_class = Class.new(::ActiveRecord::Type::Json)
      model = Class.new(::ActiveRecord::Base) do
        self.table_name = "posts"
        attribute :title, stub_class.new
      end
      expect(described_class.json_typed?(model, :title)).to be(true)
    end

    it "rejects an ActiveRecord::Type::Serialized wrapper (sibling of Type::Json, not subclass)" do
      # +serialize :col, coder: JSON+ produces this wrapper.
      expect(::ActiveRecord::Type::Serialized.ancestors).not_to include(::ActiveRecord::Type::Json)
      stub_serialized = ::ActiveRecord::Type::Serialized.new(
        ::ActiveModel::Type::String.new,
        ::ActiveRecord::Coders::JSON
      )
      stub_model = Class.new do
        define_singleton_method(:type_for_attribute) { |_name| stub_serialized }
      end
      expect(described_class.json_typed?(stub_model, :body)).to be(false)
    end

    it "rejects an ActiveRecord::Encryption::EncryptedAttributeType (sibling, not subclass)" do
      # Returning true here would write the encrypted envelope through the fast path.
      expect(::ActiveRecord::Encryption::EncryptedAttributeType.ancestors).not_to include(::ActiveRecord::Type::Json)
    end
  end

  describe ".plain_typed?" do
    it "returns true for a t.string column" do
      expect(described_class.plain_typed?(Post, :title)).to be(true)
    end

    it "returns false for a decimal attribute (BigDecimal#as_json is its String)" do
      model = Class.new(::ActiveRecord::Base) do
        self.table_name = "posts"
        attribute :title, :decimal
      end
      expect(described_class.plain_typed?(model, :title)).to be(false)
    end

    it "returns false for an inet-typed attribute (IPAddr#as_json is its String)" do
      inet_type = Class.new(::ActiveModel::Type::Value) do
        def type
          :inet
        end
      end
      model = Class.new(::ActiveRecord::Base) do
        self.table_name = "posts"
        attribute :title, inet_type.new
      end
      expect(described_class.plain_typed?(model, :title)).to be(false)
    end

    it "returns false for a serialize-coder column despite its plain type symbol" do
      # The cast value is whatever the coder returns, which +#as_json+ must still normalize.
      stub_serialized = ::ActiveRecord::Type::Serialized.new(
        ::ActiveModel::Type::String.new,
        ::ActiveRecord::Coders::JSON
      )
      stub_model = Class.new do
        define_singleton_method(:type_for_attribute) { |_name| stub_serialized }
      end
      expect(stub_serialized.type).to eq(:string)
      expect(described_class.plain_typed?(stub_model, :body)).to be(false)
    end

    it "returns false for a wrapper type exposing #subtype (PG array columns)" do
      # PG's +OID::Array+ reports its element's +#type+ but casts to a Ruby Array.
      array_like = Class.new(::ActiveModel::Type::Value) do
        def type
          :string
        end

        def subtype
          ::ActiveModel::Type::String.new
        end
      end
      model = Class.new(::ActiveRecord::Base) do
        self.table_name = "posts"
        attribute :title, array_like.new
      end
      expect(described_class.plain_typed?(model, :title)).to be(false)
    end
  end
end
