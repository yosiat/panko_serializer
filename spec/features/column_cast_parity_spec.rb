# frozen_string_literal: true

require "spec_helper"

describe "Column cast parity with 0.8.5" do
  around do |example|
    original_enabled = Panko::Config.auto_specialization.enabled
    example.run
  ensure
    Panko::Config.auto_specialization.enabled = original_enabled
  end

  context "a serialize-coder column" do
    let(:prefs) { {theme: :dark} }
    let(:expected_prefs) { {"theme" => "dark"} }
    let(:foo) { Foo.create(prefs: prefs).reload }

    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.text :prefs
        end

        serialize :prefs, coder: YAML
      end
    end

    let(:serializer_class) do
      stub_const("PrefsFooSerializer", Class.new(Panko::Serializer) do
        attributes :prefs
      end)
    end

    let(:generic_serializer_class) do
      stub_const("GenericPrefsFooSerializer", Class.new(Panko::Serializer) do
        attributes :prefs
      end)
    end

    it "normalizes the coder value through as_json on the specialized hash path" do
      expect(serializer_class.new.serialize(foo)).to eq("prefs" => expected_prefs)
    end

    it "normalizes the coder value through as_json on the generic hash path" do
      Panko::Config.auto_specialization.enabled = false

      expect(generic_serializer_class.new.serialize(foo)).to eq("prefs" => expected_prefs)
    end
  end

  context "a non-finite float column" do
    let(:foo) do
      record = Foo.create!
      Foo.connection.execute("UPDATE foos SET ratio = 9e999 WHERE id = #{record.id}")
      record.reload
    end

    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.float :ratio
        end
      end
    end

    let(:serializer_class) do
      stub_const("RatioFooSerializer", Class.new(Panko::Serializer) do
        attributes :ratio
      end)
    end

    let(:generic_serializer_class) do
      stub_const("GenericRatioFooSerializer", Class.new(Panko::Serializer) do
        attributes :ratio
      end)
    end

    it "serializes Infinity as nil on the specialized hash path" do
      expect(foo.ratio).to eq(Float::INFINITY)
      expect(serializer_class.new.serialize(foo)).to eq("ratio" => nil)
    end

    it "serializes Infinity as nil on the generic hash path" do
      Panko::Config.auto_specialization.enabled = false

      expect(generic_serializer_class.new.serialize(foo)).to eq("ratio" => nil)
    end
  end
end
