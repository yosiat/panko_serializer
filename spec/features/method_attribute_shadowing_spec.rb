# frozen_string_literal: true

require "spec_helper"

# The generated _write_one / _to_hash bodies have locals and params named
# record, writer, context, scope, filters, value, result, and child_filter
# in scope. Symbol-body method attributes dispatch with an explicit self.
# receiver — a bare method-name token for a user method with one of those
# names would silently resolve to the local instead (a `value` method even
# self-shadows to nil).
describe "Serializer methods named after generated locals" do
  let(:shadow_names) { %i[record writer context scope filters value result child_filter] }
  let(:expected_output) { shadow_names.to_h { |name| [name.to_s, "#{name}-from-method"] } }

  let(:serializer_class) do
    names = shadow_names
    stub_const("ShadowedLocalsSerializer", Class.new(Panko::Serializer) do
      attributes(*names)
      names.each { |name| define_method(name) { "#{name}-from-method" } }
    end)
  end

  it "serializes every shadow-named method to its method value (hash mode)" do
    expect(serializer_class.new.serialize({})).to eq(expected_output)
  end

  it "serializes every shadow-named method to its method value (json mode)" do
    expect(Oj.load(serializer_class.new.serialize_to_json({}))).to eq(expected_output)
  end

  context "with seam-supplied context and scope" do
    let(:seam_context) { "seam-context" }
    let(:seam_scope) { "seam-scope" }

    it "the user methods win over the same-named _write_one params" do
      output = serializer_class.new(context: seam_context, scope: seam_scope).serialize({})
      expect(output).to eq(expected_output)
    end
  end

  context "with an ActiveRecord record (specialized variant path)" do
    before do
      Temping.create(:shadow_host) do
        with_columns do |t|
          t.string :name
        end
      end
    end

    let(:record) { ShadowHost.create!(name: "unused").reload }

    it "dispatches the shadow-named methods identically" do
      expect(serializer_class.new.serialize(record)).to eq(expected_output)
    end
  end

  context "with a method made private after definition" do
    let(:private_value) { "private-value-from-method" }

    let(:private_serializer_class) do
      returned = private_value
      stub_const("PrivateShadowSerializer", Class.new(Panko::Serializer) do
        attributes :value
        define_method(:value) { returned }
        private :value
      end)
    end

    it "still reaches the method through the explicit self. receiver" do
      expect(private_serializer_class.new.serialize({})).to eq("value" => private_value)
    end
  end
end
