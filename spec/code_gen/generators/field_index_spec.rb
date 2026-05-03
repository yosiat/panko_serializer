# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"
require "shallow_generic"
require "recursive_self"
require "recursive_mutual"
require_relative "../support/field_index_parity_matcher"

# Pins the +Field-index parity+ invariant on the +Generator+ output:
# every +unless filters.drops?(N) ... end+ wrapper baked into a Generated
# Class's body must carry the same integer that the class's
# +FIELD_INDEX = {...}.freeze+ literal binds for that wrapper's Field. The
# integers come from one builder — +Generators::FieldIndex.build+ — and
# the per-Field emitters fetch by +field.name+ rather than by iteration
# position; this spec proves the discipline holds across all Field-kind
# combinations and both Output Modes so a future drift in either
# +FieldIndex.build+'s declared order or any per-emitter iteration order
# fails loudly here.
#
# Six Descriptor shapes × two Output Modes per shape — twelve cases total.
# Three of the six shapes reuse canonical fixtures (+ShallowGeneric+,
# +RecursiveSelf+, +RecursiveMutual+) so they double as a parity smoke
# test for the snapshot corpus; the other three are inline Descriptors
# pinning Field-kind combinations not represented as named fixtures
# (Attributes + MethodAttributes only; Attributes + Associations only;
# the full mix Attributes + MethodAttributes + Associations).
RSpec.describe SerializersCodeGen::Generators::FieldIndex do
  describe "field-index parity invariant" do
    config = SerializersCodeGen::Config.new

    leaf = SerializersCodeGen::Descriptor.new(
      name: "FieldIndexParityLeafSerializer",
      models: nil,
      attributes: [SerializersCodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )

    leaf_many = SerializersCodeGen::Descriptor.new(
      name: "FieldIndexParityLeafManySerializer",
      models: nil,
      attributes: [SerializersCodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )

    attributes_and_method_attributes = SerializersCodeGen::Descriptor.new(
      name: "FieldIndexParityAttrsAndMethodAttrsSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :title, source: :title)
      ],
      method_attributes: [
        SerializersCodeGen::MethodAttribute.new(name: :slug, body: ->(record) { record["title"] }),
        SerializersCodeGen::MethodAttribute.new(name: :computed, body: -> { 42 })
      ],
      associations: []
    )

    attributes_and_associations = SerializersCodeGen::Descriptor.new(
      name: "FieldIndexParityAttrsAndAssocsSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :title, source: :title)
      ],
      method_attributes: [],
      associations: [
        SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: leaf),
        SerializersCodeGen::Association.new(name: :tags, kind: :has_many, descriptor: leaf_many)
      ]
    )

    full_mix_leaf = SerializersCodeGen::Descriptor.new(
      name: "FieldIndexParityFullMixLeafSerializer",
      models: nil,
      attributes: [SerializersCodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )

    full_mix_leaf_many = SerializersCodeGen::Descriptor.new(
      name: "FieldIndexParityFullMixLeafManySerializer",
      models: nil,
      attributes: [SerializersCodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )

    full_mix = SerializersCodeGen::Descriptor.new(
      name: "FieldIndexParityFullMixSerializer",
      models: nil,
      attributes: [
        SerializersCodeGen::Attribute.new(name: :id, source: :id),
        SerializersCodeGen::Attribute.new(name: :title, source: :title)
      ],
      method_attributes: [
        SerializersCodeGen::MethodAttribute.new(name: :slug, body: ->(record) { record["title"] })
      ],
      associations: [
        SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: full_mix_leaf),
        SerializersCodeGen::Association.new(name: :tags, kind: :has_many, descriptor: full_mix_leaf_many)
      ]
    )

    cases = {
      "attributes only" => Fixtures::ShallowGeneric::DESCRIPTOR,
      "attributes + method attributes" => attributes_and_method_attributes,
      "attributes + associations (has_one + has_many)" => attributes_and_associations,
      "full mix (attributes + method attributes + associations)" => full_mix,
      "recursive self-reference" => Fixtures::RecursiveSelf::DESCRIPTOR,
      "mutual recursion" => Fixtures::RecursiveMutual::DESCRIPTOR
    }

    cases.each do |label, descriptor|
      %i[json hash].each do |mode|
        context "with #{label} (#{mode} mode)" do
          it "every `unless filters.drops?(N)` wrapper's N matches FIELD_INDEX[name]" do
            source = SerializersCodeGen::Generator.new.emit(descriptor, output: mode, config: config)
            expect(source).to have_field_index_parity
          end
        end
      end
    end
  end
end
