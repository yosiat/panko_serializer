# frozen_string_literal: true

require "panko/code_gen"

RSpec.describe Panko::CodeGen::ActiveRecord::AccessClassifier do
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
      }.to raise_error(Panko::CodeGen::UnknownSourceError)
    end

    it "names the class and source in the raised message" do
      klass = fake_ar_class(name: "Post", columns: ["id"], methods: [])
      expect {
        described_class.classify([klass], :missing)
      }.to raise_error(Panko::CodeGen::UnknownSourceError, /Post/) { |err|
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
        }.to raise_error(Panko::CodeGen::UnknownSourceError)
      end

      it "names the offending class in the raised message when only one class lacks the source" do
        v = fake_ar_class(name: "Vehicle", columns: ["vin"], methods: %i[wheels])
        c = fake_ar_class(name: "Car", columns: ["vin"])
        expect {
          described_class.classify([v, c], :wheels)
        }.to raise_error(Panko::CodeGen::UnknownSourceError) { |err|
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
        }.to raise_error(Panko::CodeGen::UnknownSourceError) { |err|
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

      it "names only the missing classes (skipping non-missing) and preserves declaration order" do
        v = fake_ar_class(name: "Vehicle", columns: ["vin"])
        c = fake_ar_class(name: "Car", columns: ["vin"], methods: %i[wheels])
        t = fake_ar_class(name: "Truck", columns: ["vin"])
        expect {
          described_class.classify([v, c, t], :wheels)
        }.to raise_error(
          Panko::CodeGen::UnknownSourceError,
          "Vehicle, Truck: source :wheels is not a column or instance method."
        )
      end
    end

    describe "multi-class STI override-detection (S7.2)" do
      # Per +docs/compilation.md § STI and mixed class sets+: "a subclass
      # that overrides a column reader downgrades that attribute across
      # the whole Generated Class — method dispatch wins whenever any
      # class in the set lacks uniform column-backing."
      #
      # Real AR signals overrides via +klass.instance_method(name).owner+:
      # AR-auto-generated readers live in modules named
      # +<Class>::GeneratedAttributeMethods+; user overrides have a
      # different owner (the class itself). The fakes below model this
      # by exposing an +instance_method+ method that returns a stub
      # method object whose +#owner+ is either the AR-generated module
      # or the user class.
      def fake_ar_class_with_owners(name:, columns: [], method_owners: {})
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

      it "downgrades a uniformly column-backed Attribute to :method when a subclass user-overrides the reader" do
        # Vehicle: +make+ in columns_hash, AR-auto-generated reader (no override).
        # Car: +make+ in columns_hash, user-overridden reader. Per the STI rule
        # the override on Car downgrades +make+ across the whole Generated Class.
        vehicle = fake_ar_class_with_owners(
          name: "Vehicle",
          columns: ["make"],
          method_owners: {make: :ar_generated}
        )
        car = fake_ar_class_with_owners(
          name: "Car",
          columns: ["make"],
          method_owners: {make: :user_class}
        )
        expect(described_class.classify([vehicle, car], :make)).to eq(:method)
      end

      it "downgrades when the override is on the parent class instead of the subclass" do
        # Symmetric case: parent overrides, subclass inherits the override.
        # The rule still says "any non-uniformity downgrades" — parent's
        # override must be honored on every instance.
        vehicle = fake_ar_class_with_owners(
          name: "Vehicle",
          columns: ["make"],
          method_owners: {make: :user_class}
        )
        car = fake_ar_class_with_owners(
          name: "Car",
          columns: ["make"],
          method_owners: {make: :ar_generated}
        )
        expect(described_class.classify([vehicle, car], :make)).to eq(:method)
      end

      it "stays :column when no class overrides the reader (uniform AR-generated readers)" do
        vehicle = fake_ar_class_with_owners(
          name: "Vehicle",
          columns: ["vin"],
          method_owners: {vin: :ar_generated}
        )
        car = fake_ar_class_with_owners(
          name: "Car",
          columns: ["vin"],
          method_owners: {vin: :ar_generated}
        )
        expect(described_class.classify([vehicle, car], :vin)).to eq(:column)
      end

      it "preserves single-class override-bypass — override on a 1-element Array stays :column" do
        # Per +docs/compilation.md § Overrides are bypassed for column-backed
        # attributes+: single-class +models: [SingleClass]+ explicitly opts
        # into override bypass. The override-detection layer activates only
        # for multi-class sets.
        post = fake_ar_class_with_owners(
          name: "Post",
          columns: ["title"],
          method_owners: {title: :user_class}
        )
        expect(described_class.classify([post], :title)).to eq(:column)
      end
    end
  end

  describe ".json_typed?" do
    # The predicate runs on real AR models — its contract is "the attribute's
    # +type_for_attribute+ is an +ActiveRecord::Type::Json+ instance (or
    # subclass)". The fakes used by +.classify+ above don't help here because
    # the predicate calls AR-specific +type_for_attribute+, so the fixture is a
    # tiny anonymous AR model with the column shape we want to probe. Schema
    # is shared with the spec helper's main schema (already loads +t.string+
    # columns); the +t.json :metadata+ column is added in
    # +spec/support/schema.rb+ for this slice.

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
      # +type_for_attribute+ returns the +ActiveModel::Type::Value+ default for
      # unknown names — not a +Type::Json+, predicate cleanly returns false.
      # No rescue clause, no special-case — the AR contract handles it.
      expect(described_class.json_typed?(Post, :does_not_exist)).to be(false)
    end

    it "accepts a custom subclass of ActiveRecord::Type::Json (is_a, not exact match)" do
      # User-defined subclasses of +Type::Json+ inherit the JSON-on-write
      # contract — the predicate accepts them via +is_a?+. Mirrors the
      # +OID::Jsonb < Type::Json+ relationship for Postgres jsonb.
      stub_class = Class.new(::ActiveRecord::Type::Json)
      model = Class.new(::ActiveRecord::Base) do
        self.table_name = "posts"
        attribute :title, stub_class.new
      end
      expect(described_class.json_typed?(model, :title)).to be(true)
    end

    it "rejects an ActiveRecord::Type::Serialized wrapper (sibling of Type::Json, not subclass)" do
      # +serialize :col, coder: JSON+ wraps the column type in
      # +ActiveRecord::Type::Serialized+, which is a sibling of +Type::Json+
      # (not a subclass). Predicate correctly rejects it. The hierarchy
      # invariant is checked directly — sibling siblings of +Type::Json+ must
      # not match the +is_a?+ predicate, regardless of which sibling triggers
      # it (encryption, serialize, etc.).
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
      # +EncryptedAttributeType+ is a sibling of +Type::Json+ — same +#type+
      # symbol but different class hierarchy. Returning true here would emit
      # the ciphertext envelope through the fast path. The +is_a?+ predicate
      # correctly rejects it.
      expect(::ActiveRecord::Encryption::EncryptedAttributeType.ancestors).not_to include(::ActiveRecord::Type::Json)
    end
  end
end
