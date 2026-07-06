# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

RSpec.describe Panko::CodeGen::CompileCache do
  let(:cache) { described_class.new }
  let(:descriptor) {
    Panko::CodeGen::Descriptor.new(
      name: "ADescriptor", models: nil,
      attributes: [], method_attributes: [], associations: []
    )
  }

  describe "#get / #set" do
    it "returns nil for an unknown Descriptor" do
      expect(cache.get(descriptor)).to be_nil
    end

    it "round-trips a Generated Class via #set + #get keyed by identity" do
      klass = Class.new
      cache.set(descriptor, klass)
      expect(cache.get(descriptor)).to equal(klass)
    end

    it "treats structurally-equal-but-distinct Descriptors as distinct keys" do
      twin = Panko::CodeGen::Descriptor.new(
        name: "ADescriptor", models: nil,
        attributes: [], method_attributes: [], associations: []
      )
      klass = Class.new
      cache.set(descriptor, klass)
      expect(cache.get(twin)).to be_nil
    end

    # S18.4 row: two Descriptors with the same +name+ / +models+ /
    # Field arrays but different +parent_class+ values must map to
    # distinct cache entries. Pinned explicitly to make the cache's
    # +__id__+-keyed contract visible for the new field — the cache
    # already keys on Descriptor identity, so any new +Data.define+
    # field automatically participates; this row guards against a
    # future regression that, e.g., introduces a structural
    # +==+/+#hash+ short-circuit on the cache lookup.
    it "treats two Descriptors differing only by parent_class as distinct keys" do
      bare_parent = Class.new
      with_parent = Panko::CodeGen::Descriptor.new(
        name: "ADescriptor", models: nil,
        attributes: [], method_attributes: [], associations: [],
        parent_class: bare_parent
      )
      klass_without = Class.new
      klass_with = Class.new
      cache.set(descriptor, klass_without)
      cache.set(with_parent, klass_with)
      expect(cache.get(descriptor)).to equal(klass_without)
      expect(cache.get(with_parent)).to equal(klass_with)
    end
  end

  describe "#fetch" do
    it "yields on miss + caches the block's return value" do
      klass = Class.new
      result = cache.fetch(descriptor) { klass }
      expect(result).to equal(klass)
      expect(cache.get(descriptor)).to equal(klass)
    end

    it "skips the block on hit + returns the cached value" do
      klass = Class.new
      cache.set(descriptor, klass)
      result = cache.fetch(descriptor) { raise "should not yield" }
      expect(result).to equal(klass)
    end
  end

  describe "#lookup_or_compile" do
    it "returns the cached class on hit, never yielding" do
      klass = Class.new
      cache.set(descriptor, klass)
      expect(cache.lookup_or_compile(descriptor) { raise "should not yield" }).to equal(klass)
    end

    it "yields on miss, then returns whatever the block populated under the Descriptor's identity" do
      klass = Class.new
      result = cache.lookup_or_compile(descriptor) { cache.set(descriptor, klass) }
      expect(result).to equal(klass)
      expect(cache.get(descriptor)).to equal(klass)
    end

    it "exposes the in-progress class to recursive #lookup_or_compile calls inside the block " \
       "(entry added before the block descends so a self-referential lookup short-circuits)" do
      in_progress = Class.new
      observed = nil
      cache.lookup_or_compile(descriptor) do
        cache.set(descriptor, in_progress)
        observed = cache.lookup_or_compile(descriptor) { raise "recursive miss should be impossible" }
      end
      expect(observed).to equal(in_progress)
    end

    it "is identity-keyed — two distinct Descriptor instances each get their own block invocation" do
      twin = Panko::CodeGen::Descriptor.new(
        name: "ADescriptor", models: nil,
        attributes: [], method_attributes: [], associations: []
      )
      one_klass = Class.new
      two_klass = Class.new
      cache.lookup_or_compile(descriptor) { cache.set(descriptor, one_klass) }
      cache.lookup_or_compile(twin) { cache.set(twin, two_klass) }
      expect(cache.get(descriptor)).to equal(one_klass)
      expect(cache.get(twin)).to equal(two_klass)
    end
  end
end
