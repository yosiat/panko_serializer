# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

RSpec.describe Panko::CodeGen::Generators::CycleMembership do
  def descriptor(name, associations: [])
    Panko::CodeGen::Descriptor.new(
      name: name, models: nil,
      attributes: [], method_attributes: [], associations: associations
    )
  end

  def has_many(target, name: :children)
    Panko::CodeGen::Association.new(name: name, kind: :has_many, descriptor: target)
  end

  describe ".cyclic_descriptor_ids" do
    it "returns an empty Hash for an acyclic single Descriptor (no associations)" do
      d = descriptor("D")
      expect(described_class.cyclic_descriptor_ids(d)).to eq({})
    end

    it "returns an empty Hash for an acyclic tree (parent → distinct child)" do
      child = descriptor("Child")
      parent = descriptor("Parent", associations: [has_many(child)])
      expect(described_class.cyclic_descriptor_ids(parent)).to eq({})
    end

    it "ignores self-loop edges — a Descriptor with only a self-edge is not cyclic " \
       "(self-recursion is handled by the @<name>_serializer = self shortcut)" do
      d = descriptor("D")
      d.associations << has_many(d, name: :replies)
      expect(described_class.cyclic_descriptor_ids(d)).to eq({})
    end

    it "marks both nodes of a 2-cycle (A → B → A)" do
      a = descriptor("A")
      b = descriptor("B")
      a.associations << has_many(b, name: :bs)
      b.associations << has_many(a, name: :as)
      ids = described_class.cyclic_descriptor_ids(a)
      expect(ids).to include(a.__id__ => true, b.__id__ => true)
      expect(ids.size).to eq(2)
    end

    it "marks all three nodes of a 3-cycle (A → B → C → A)" do
      a = descriptor("A")
      b = descriptor("B")
      c = descriptor("C")
      a.associations << has_many(b, name: :bs)
      b.associations << has_many(c, name: :cs)
      c.associations << has_many(a, name: :as)
      ids = described_class.cyclic_descriptor_ids(a)
      expect(ids).to include(a.__id__ => true, b.__id__ => true, c.__id__ => true)
      expect(ids.size).to eq(3)
    end

    it "leaves an acyclic sibling unmarked when its sibling participates in a cycle " \
       "(A → B with B → A on a cycle, A → C with C acyclic)" do
      a = descriptor("A")
      b = descriptor("B")
      c = descriptor("C")
      a.associations << has_many(b, name: :bs)
      a.associations << has_many(c, name: :cs)
      b.associations << has_many(a, name: :as)
      ids = described_class.cyclic_descriptor_ids(a)
      expect(ids).to include(a.__id__ => true, b.__id__ => true)
      expect(ids).not_to have_key(c.__id__)
    end

    it "leaves an acyclic root unmarked when its descendant subtree is cyclic " \
       "(Wrapper → A, with A → B → A cycle)" do
      wrapper = descriptor("Wrapper")
      a = descriptor("A")
      b = descriptor("B")
      a.associations << has_many(b, name: :bs)
      b.associations << has_many(a, name: :as)
      wrapper.associations << has_many(a, name: :a)
      ids = described_class.cyclic_descriptor_ids(wrapper)
      expect(ids).to include(a.__id__ => true, b.__id__ => true)
      expect(ids).not_to have_key(wrapper.__id__)
    end

    it "is identity-keyed — two structurally-equal Descriptors get distinct membership decisions" do
      a = descriptor("A")
      b1 = descriptor("B")
      b2 = descriptor("B")
      a.associations << has_many(b1, name: :b1)
      a.associations << has_many(b2, name: :b2)
      b1.associations << has_many(a, name: :back)
      ids = described_class.cyclic_descriptor_ids(a)
      expect(ids).to have_key(b1.__id__)
      expect(ids).not_to have_key(b2.__id__)
    end

    it "marks every node on a cycle even when one back-edge is reached via a shorter path first " \
       "(A → X → A short cycle visited before A → Y → X → A longer cycle through Y)" do
      a = descriptor("A")
      x = descriptor("X")
      y = descriptor("Y")
      a.associations << has_many(x, name: :xs)
      a.associations << has_many(y, name: :ys)
      y.associations << has_many(x, name: :back)
      x.associations << has_many(a, name: :back)
      ids = described_class.cyclic_descriptor_ids(a)
      expect(ids).to include(a.__id__ => true, x.__id__ => true, y.__id__ => true)
    end

    it "marks a Descriptor with both a self-loop and a mutual cycle as cyclic " \
       "(A → A self-loop AND A → B → A mutual cycle — mutual edge wins)" do
      a = descriptor("A")
      b = descriptor("B")
      a.associations << has_many(a, name: :selves)
      a.associations << has_many(b, name: :bs)
      b.associations << has_many(a, name: :as)
      ids = described_class.cyclic_descriptor_ids(a)
      expect(ids).to include(a.__id__ => true, b.__id__ => true)
    end
  end
end
