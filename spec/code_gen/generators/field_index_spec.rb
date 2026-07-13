# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "shallow_generic"
require "recursive_self"
require "recursive_mutual"
require_relative "../support/field_index_parity_matcher"

# Pins the +Field-index parity+ invariant on the +Generator+ output:
# every +unless filters.drops?(N) ... end+ wrapper baked into a Generated
# Class's body must carry the same integer that the class's
# +FIELD_INDEX = {...}.freeze+ literal binds for that wrapper's Field. The
# integers come from one builder — +Generators::FieldIndex.build+ — and
# the per-Field emitters fetch by the field's filter key (+name+ for value
# Fields, +source+ for Associations) rather than by iteration
# position; this spec proves the discipline holds across all Field-kind
# combinations and both Output Modes so a future drift in either
# +FieldIndex.build+'s declared order or any per-emitter iteration order
# fails loudly here.
#
# Seven Descriptor shapes × two Output Modes per shape — fourteen cases
# total. Three of the seven shapes reuse canonical fixtures
# (+ShallowGeneric+, +RecursiveSelf+, +RecursiveMutual+) so they double
# as a parity smoke test for the snapshot corpus; the other four are
# inline Descriptors pinning Field-kind combinations not represented as
# named fixtures (Attributes + MethodAttributes only; Attributes +
# Associations only; the full mix Attributes + MethodAttributes +
# Associations; an aliased Association whose +source+ differs from its
# +name+).
RSpec.describe Panko::CodeGen::Generators::FieldIndex do
  describe "field-index parity invariant" do
    config = Panko::CodeGen::Config.new

    leaf = Panko::CodeGen::Descriptor.new(
      name: "FieldIndexParityLeafSerializer",
      model: nil,
      attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )

    leaf_many = Panko::CodeGen::Descriptor.new(
      name: "FieldIndexParityLeafManySerializer",
      model: nil,
      attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )

    attributes_and_method_attributes = Panko::CodeGen::Descriptor.new(
      name: "FieldIndexParityAttrsAndMethodAttrsSerializer",
      model: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :title, source: :title)
      ],
      method_attributes: [
        Panko::CodeGen::MethodAttribute.new(name: :slug, body: ->(record) { record["title"] }),
        Panko::CodeGen::MethodAttribute.new(name: :computed, body: -> { 42 })
      ],
      associations: []
    )

    attributes_and_associations = Panko::CodeGen::Descriptor.new(
      name: "FieldIndexParityAttrsAndAssocsSerializer",
      model: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :title, source: :title)
      ],
      method_attributes: [],
      associations: [
        Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: leaf),
        Panko::CodeGen::Association.new(name: :tags, kind: :has_many, descriptor: leaf_many)
      ]
    )

    full_mix_leaf = Panko::CodeGen::Descriptor.new(
      name: "FieldIndexParityFullMixLeafSerializer",
      model: nil,
      attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )

    full_mix_leaf_many = Panko::CodeGen::Descriptor.new(
      name: "FieldIndexParityFullMixLeafManySerializer",
      model: nil,
      attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )

    full_mix = Panko::CodeGen::Descriptor.new(
      name: "FieldIndexParityFullMixSerializer",
      model: nil,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :title, source: :title)
      ],
      method_attributes: [
        Panko::CodeGen::MethodAttribute.new(name: :slug, body: ->(record) { record["title"] })
      ],
      associations: [
        Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: full_mix_leaf),
        Panko::CodeGen::Association.new(name: :tags, kind: :has_many, descriptor: full_mix_leaf_many)
      ]
    )

    aliased_leaf = Panko::CodeGen::Descriptor.new(
      name: "FieldIndexParityAliasedLeafSerializer",
      model: nil,
      attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )

    aliased_association = Panko::CodeGen::Descriptor.new(
      name: "FieldIndexParityAliasedAssocSerializer",
      model: nil,
      attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: [
        Panko::CodeGen::Association.new(name: :history, kind: :has_many, descriptor: aliased_leaf, source: :comments)
      ]
    )

    cases = {
      "attributes only" => Fixtures::ShallowGeneric::DESCRIPTOR,
      "attributes + method attributes" => attributes_and_method_attributes,
      "attributes + associations (has_one + has_many)" => attributes_and_associations,
      "full mix (attributes + method attributes + associations)" => full_mix,
      "aliased association (source != name)" => aliased_association,
      "recursive self-reference" => Fixtures::RecursiveSelf::DESCRIPTOR,
      "mutual recursion" => Fixtures::RecursiveMutual::DESCRIPTOR
    }

    cases.each do |label, descriptor|
      %i[json hash].each do |mode|
        context "with #{label} (#{mode} mode)" do
          it "every `unless filters.drops?(N)` wrapper's N matches FIELD_INDEX[name]" do
            source = Panko::CodeGen::Generator.new.emit(descriptor, output: mode, config: config)
            expect(source).to have_field_index_parity
          end
        end
      end
    end

    context "with an aliased association (source != name)" do
      it "keys the association by its source, not its output name" do
        expect(described_class.build(aliased_association)).to eq(id: 0, comments: 1)
      end
    end
  end
end
