# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

RSpec.describe "Association variants: one child body per record class" do
  let(:stored) { '{"b": 1.50, "b": 2}' }
  let(:note_text) { "plain text" }
  let(:other_record) { Struct.new(:id, :metadata).new(0, {"k" => 1}) }

  def child_descriptor(model: nil, name: "ChildSerializer")
    Panko::CodeGen::Descriptor.new(
      name: name,
      model: model,
      parent_class: Fixtures::BaseSerializer,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :metadata, source: :metadata)
      ],
      method_attributes: [],
      associations: []
    )
  end

  def association(kind:, variants:)
    Panko::CodeGen::Association.new(
      name: :items,
      kind: kind,
      descriptor: child_descriptor,
      variants: variants
    )
  end

  def parent_descriptor(association)
    Panko::CodeGen::Descriptor.new(
      name: "ParentSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [],
      method_attributes: [],
      associations: [association]
    )
  end

  let(:variants) do
    [
      child_descriptor(model: PlainPost, name: "ChildSerializer_Post"),
      child_descriptor(model: PlainNote, name: "ChildSerializer_Note")
    ]
  end

  let(:post) do
    PlainPost.create!.tap { |record| PlainPost.where(id: record.id).update_all(["metadata = ?", stored]) }
  end
  let(:note) { PlainNote.create!(metadata: note_text) }
  let(:parent_record) { Struct.new(:items).new([PlainPost.find(post.id), note, other_record]) }

  def serialize(descriptor, output)
    instance = Panko::CodeGen.compile(descriptor, output: output).new(descriptor: descriptor)
    instance.serialize_one(parent_record)
  end

  after do
    PlainPost.delete_all
    PlainNote.delete_all
  end

  describe "has_many" do
    let(:descriptor) { parent_descriptor(association(kind: :has_many, variants: variants)) }

    it "writes each record with the variant for its exact class, others with the base child" do
      expect(serialize(descriptor, :json)).to eq(
        %({"items":[{"id":#{post.id},"metadata":#{stored}},{"id":#{note.id},"metadata":"#{note_text}"},{"id":0,"metadata":{"k":1}}]})
      )
    end

    it "returns the typed values in hash mode" do
      expect(serialize(descriptor, :hash)).to eq(
        "items" => [
          {"id" => post.id, "metadata" => Oj.load(stored)},
          {"id" => note.id, "metadata" => note_text},
          {"id" => 0, "metadata" => {"k" => 1}}
        ]
      )
    end
  end

  describe "has_one" do
    let(:descriptor) { parent_descriptor(association(kind: :has_one, variants: variants)) }
    let(:parent_record) { Struct.new(:items).new(note) }

    it "writes the record with the variant for its class" do
      expect(serialize(descriptor, :json)).to eq(%({"items":{"id":#{note.id},"metadata":"#{note_text}"}}))
    end

    it "returns the same value in hash mode" do
      expect(serialize(descriptor, :hash)).to eq("items" => {"id" => note.id, "metadata" => note_text})
    end
  end

  describe "a subclass of a variant's model" do
    let(:make) { "small car" }
    let(:car) { Car.create!(vin: "1", make: make) }
    let(:parent_record) { Struct.new(:items).new([car]) }

    def vehicle_child(model, name)
      Panko::CodeGen::Descriptor.new(
        name: name,
        model: model,
        parent_class: Fixtures::BaseSerializer,
        attributes: [Panko::CodeGen::Attribute.new(name: :make, source: :make)],
        method_attributes: [],
        associations: []
      )
    end

    def vehicles_descriptor(variant_models)
      variants = variant_models.map { |model| vehicle_child(model, "VehicleChild_#{model.name}") }
      parent_descriptor(
        Panko::CodeGen::Association.new(
          name: :items, kind: :has_many, descriptor: vehicle_child(nil, "VehicleChild"), variants: variants
        )
      )
    end

    after { Vehicle.delete_all }

    it "is written by its own variant when declared after its parent" do
      expect(serialize(vehicles_descriptor([Vehicle, Car]), :json)).to eq(%({"items":[{"make":"#{make.titleize}"}]}))
    end

    it "is written by the base child when only its parent is declared" do
      expect(serialize(vehicles_descriptor([Vehicle]), :json)).to eq(%({"items":[{"make":"#{make.titleize}"}]}))
    end
  end

  describe "validation" do
    it "rejects a variant without a model" do
      expect { association(kind: :has_many, variants: [child_descriptor]) }
        .to raise_error(Panko::CodeGen::DescriptorError, /every variant needs a named model/)
    end

    it "rejects two variants for one model" do
      twins = [child_descriptor(model: PlainPost, name: "A"), child_descriptor(model: PlainPost, name: "B")]

      expect { association(kind: :has_many, variants: twins) }
        .to raise_error(Panko::CodeGen::DescriptorError, /models must be distinct/)
    end

    it "rejects a variant that is not a Descriptor" do
      expect { association(kind: :has_many, variants: [PlainPost]) }
        .to raise_error(Panko::CodeGen::DescriptorError, /Association#variants/)
    end
  end
end
