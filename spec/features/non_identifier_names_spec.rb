# frozen_string_literal: true

require "spec_helper"

describe "Output names that are not Ruby identifiers" do
  def define_serializer(name, &block)
    stub_const(name, Class.new(Panko::Serializer, &block))
  end

  let(:digit_name) { :"2faEnabled" }
  let(:quote_name) { :'say "hi"' }
  let(:interpolation_name) { :"\#{raise \"evaluated\"}" }
  let(:dash_name) { :"user-name" }

  context "with aliased attributes on a PORO" do
    let(:record) { Struct.new(:twofa_enabled, :greeting, :raw, :name).new(true, "hi", "r", "Alice") }
    let(:serializer) do
      names = [digit_name, quote_name, interpolation_name, dash_name]
      define_serializer("AliasedNamesSerializer") do
        aliases twofa_enabled: names[0], greeting: names[1], raw: names[2], name: names[3]
      end
    end

    it "writes each name as the output key" do
      expect(record).to serialized_as(serializer,
        digit_name.to_s => true,
        quote_name.to_s => "hi",
        interpolation_name.to_s => "r",
        dash_name.to_s => "Alice")
    end
  end

  context "with Hash records whose keys are not identifiers" do
    let(:record) { {dash_name.to_s => "Alice", quote_name.to_s => "hi"} }
    let(:serializer) do
      names = [dash_name, quote_name]
      define_serializer("HashKeysSerializer") { attributes(*names) }
    end

    it "reads and writes each key" do
      expect(record).to serialized_as(serializer, dash_name.to_s => "Alice", quote_name.to_s => "hi")
    end
  end

  context "with a method attribute whose method name is not an identifier" do
    let(:serializer) do
      name = digit_name
      define_serializer("MethodNameSerializer") do
        attributes name
        define_method(name) { 42 }
      end
    end

    it "writes the method's value under the name" do
      expect(Object.new).to serialized_as(serializer, digit_name.to_s => 42)
    end
  end

  context "with associations named with non-identifiers" do
    let(:child_class) { Struct.new(:id) }
    let(:record) { Struct.new(:child, :children).new(child_class.new(1), [child_class.new(2)]) }
    let(:child_serializer) { define_serializer("NamedChildSerializer") { attributes :id } }
    let(:serializer) do
      child = child_serializer
      names = [digit_name, dash_name]
      define_serializer("NamedAssociationsSerializer") do
        has_one :child, serializer: child, name: names[0]
        has_many :children, serializer: child, name: names[1]
      end
    end

    it "writes each association under its name" do
      expect(record).to serialized_as(serializer,
        digit_name.to_s => {"id" => 1},
        dash_name.to_s => [{"id" => 2}])
    end

    it "filters each association by its source" do
      expect(record).to serialized_as(-> { serializer.new(only: [:child]) }, digit_name.to_s => {"id" => 1})
    end
  end

  context "with an Active Record model on the specialized path" do
    let(:created_at) { Time.utc(2026, 1, 2, 3, 4, 5) }
    let(:account) { Account.create(twofa_enabled: true, signed_up_at: created_at).reload }
    let(:serializer) do
      names = [digit_name, dash_name]
      define_serializer("AccountSerializer") do
        aliases twofa_enabled: names[0], signed_up_at: names[1]
      end
    end

    before do
      Temping.create(:account) do
        with_columns do |t|
          t.boolean :twofa_enabled
          t.datetime :signed_up_at
        end
      end
    end

    it "writes each column under its name" do
      expect(account).to serialized_as(serializer,
        digit_name.to_s => true,
        dash_name.to_s => "2026-01-02T03:04:05.000Z")
    end
  end
end
