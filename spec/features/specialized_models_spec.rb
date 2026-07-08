# frozen_string_literal: true

require "spec_helper"

describe "Specialized models" do
  let(:name) { "Jane Doe" }
  let(:address) { "1 Infinite Loop" }
  let(:foo) { Foo.create(name: name, address: address).reload }

  before do
    Temping.create(:foo) do
      with_columns do |t|
        t.string :name
        t.string :address
      end
    end
  end

  let(:generic_serializer) do
    stub_const("GenericFooSerializer", Class.new(Panko::Serializer) do
      attributes :name, :address
    end)
  end

  let(:specialized_serializer) do
    stub_const("SpecializedFooSerializer", Class.new(Panko::Serializer) do
      models [Foo]
      attributes :name, :address
    end)
  end

  it "serializes an AR record declaring models" do
    expect(foo).to serialized_as(specialized_serializer,
      "name" => name,
      "address" => address)
  end

  it "produces byte-identical output to the generic path" do
    specialized = specialized_serializer.new.serialize_to_json(foo)
    generic = generic_serializer.new.serialize_to_json(foo)

    expect(specialized).to eq(generic)
  end

  context "with a method attribute" do
    let(:specialized_with_method) do
      stub_const("SpecializedFooWithMethodSerializer", Class.new(Panko::Serializer) do
        models [Foo]
        attributes :name, :shouting_name

        def shouting_name
          object.name.upcase
        end
      end)
    end

    it "dispatches the method on the specialized path" do
      expect(foo).to serialized_as(specialized_with_method,
        "name" => name,
        "shouting_name" => name.upcase)
    end
  end

  context "when an attribute resolves to neither a column nor a method on the model" do
    let(:unresolved_attribute) { :not_a_column }

    let(:invalid_specialized) do
      attribute = unresolved_attribute
      stub_const("InvalidSpecializedFooSerializer", Class.new(Panko::Serializer) do
        models [Foo]
        attributes :name, attribute
      end)
    end

    let(:invalid_generic) do
      attribute = unresolved_attribute
      stub_const("InvalidGenericFooSerializer", Class.new(Panko::Serializer) do
        attributes :name, attribute
      end)
    end

    # The specialized path validates sources at compile time, so an
    # unresolved attribute is caught before serialization — proving the
    # serializer routes through the Specialized path rather than the Generic
    # one, which only fails at runtime.
    it "raises UnknownSourceError at compile time" do
      expect { invalid_specialized.new.serialize_to_json(foo) }
        .to raise_error(Panko::CodeGen::UnknownSourceError)
    end

    it "differs from the generic path, which raises a runtime NoMethodError" do
      expect { invalid_generic.new.serialize_to_json(foo) }
        .to raise_error(NoMethodError)
    end
  end
end
