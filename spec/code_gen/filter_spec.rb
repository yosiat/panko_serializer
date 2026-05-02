# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"

RSpec.describe SerializersCodeGen::Filter do
  describe ".wrap" do
    it "returns Filter::NONE for nil" do
      expect(described_class.wrap(nil)).to equal(SerializersCodeGen::Filter::NONE)
    end

    it "returns Filter::NONE for an empty Hash" do
      expect(described_class.wrap({})).to equal(SerializersCodeGen::Filter::NONE)
    end

    it "returns Filter::NONE for nil even when a +field_index+ is supplied" do
      expect(described_class.wrap(nil, {id: 0})).to equal(SerializersCodeGen::Filter::NONE)
    end

    it "returns a Filter::Indexed for a non-empty Hash" do
      indexed = described_class.wrap({only: [:id]}, {id: 0, title: 1})
      expect(indexed).to be_a(SerializersCodeGen::Filter::Indexed::Bits)
    end

    it "raises ArgumentError when a non-empty Hash is wrapped without a +field_index+" do
      expect { described_class.wrap({only: [:id]}) }
        .to raise_error(ArgumentError, /field_index/)
    end

    describe ":only + :except co-supplied" do
      # Per +docs/filters.md § Rules+ ("+:only+ and +:except+ at the
      # same level are mutually exclusive. Supplying both is a caller
      # error and raises +ArgumentError+ at the first +_write_one+ /
      # +_to_hash+ entry on that level."). +Filter.wrap+ runs once per
      # +serialize_*+ call and walks the nested filter Hash recursively
      # so the emitted body can stay free of validation branches.
      it "raises ArgumentError when supplied at the top level" do
        expect { described_class.wrap({only: [:id], except: [:title]}, {id: 0, title: 1}) }
          .to raise_error(ArgumentError, /only.*except/i)
      end

      it "raises ArgumentError when supplied at a nested Association level" do
        expect {
          described_class.wrap({author: {only: [:id], except: [:name]}}, {id: 0, author: 1})
        }.to raise_error(ArgumentError, /only.*except/i)
      end

      it "raises ArgumentError when supplied at a deeply-nested level" do
        expect {
          described_class.wrap(
            {comments: {replies: {only: [:id], except: [:body]}}},
            {id: 0, comments: 1}
          )
        }.to raise_error(ArgumentError, /only.*except/i)
      end

      it "raises ArgumentError when co-supplied under an unknown top-level Source key" do
        # The validator walks every Hash value regardless of whether the
        # key matches a known Source on the +FIELD_INDEX+. A typo in a
        # Source name does not silence the co-supply error — caller still
        # learns about the mutually-exclusive misuse rather than seeing
        # a silently unfiltered result.
        expect {
          described_class.wrap(
            {totally_unknown: {only: [:a], except: [:b]}},
            {id: 0, title: 1}
          )
        }.to raise_error(ArgumentError, /only.*except/i)
      end

      it "does not raise when only +:only+ is supplied at every level" do
        expect {
          described_class.wrap({only: [:id], author: {only: [:name]}}, {id: 0, author: 1})
        }.not_to raise_error
      end

      it "does not raise when only +:except+ is supplied at every level" do
        expect {
          described_class.wrap({except: [:id], author: {except: [:name]}}, {id: 0, author: 1})
        }.not_to raise_error
      end

      it "does not raise when +:only+ at parent and +:except+ at a child are split across levels" do
        expect {
          described_class.wrap({only: [:id, :author], author: {except: [:name]}}, {id: 0, author: 1})
        }.not_to raise_error
      end
    end
  end

  describe "::NONE" do
    let(:none) { SerializersCodeGen::Filter::NONE }

    it "is frozen" do
      expect(none).to be_frozen
    end

    it "is a stable singleton via #equal?" do
      expect(none).to equal(SerializersCodeGen::Filter::NONE)
    end

    it "drops? returns false for any integer index" do
      expect(none.drops?(0)).to be(false)
      expect(none.drops?(42)).to be(false)
    end

    it "child returns self for any source name" do
      expect(none.child(:author)).to equal(none)
      expect(none.child(:comments)).to equal(none)
    end

    it "none? returns true" do
      expect(none.none?).to be(true)
    end
  end

  describe "::Indexed" do
    it "exposes INDEXED_BITS_THRESHOLD = 63 (Integer#[] tagged-Fixnum boundary)" do
      expect(SerializersCodeGen::Filter::Indexed::INDEXED_BITS_THRESHOLD).to eq(63)
    end

    describe ".build" do
      it "picks the Bits representation when FIELD_INDEX.size <= 63" do
        field_index = (0..62).each_with_object({}) { |i, h| h[:"f#{i}"] = i }
        expect(field_index.size).to eq(63)
        filter = SerializersCodeGen::Filter::Indexed.build({only: [:f0]}, field_index)
        expect(filter).to be_a(SerializersCodeGen::Filter::Indexed::Bits)
      end

      it "picks the Array representation when FIELD_INDEX.size > 63" do
        field_index = (0..63).each_with_object({}) { |i, h| h[:"f#{i}"] = i }
        expect(field_index.size).to eq(64)
        filter = SerializersCodeGen::Filter::Indexed.build({only: [:f0]}, field_index)
        expect(filter).to be_a(SerializersCodeGen::Filter::Indexed::Array)
      end
    end

    shared_examples "an Indexed Filter representation" do |field_count:|
      let(:field_index) do
        (0...field_count).each_with_object({}) { |i, h| h[:"f#{i}"] = i }
      end

      describe "#drops?" do
        it "drops every Field except the listed +only:+ names" do
          filter = SerializersCodeGen::Filter::Indexed.build({only: [:f0, :f3]}, field_index)
          expect(filter.drops?(0)).to be(false)
          expect(filter.drops?(1)).to be(true)
          expect(filter.drops?(2)).to be(true)
          expect(filter.drops?(3)).to be(false)
        end

        it "keeps every Field except the listed +except:+ names" do
          filter = SerializersCodeGen::Filter::Indexed.build({except: [:f1]}, field_index)
          expect(filter.drops?(0)).to be(false)
          expect(filter.drops?(1)).to be(true)
          expect(filter.drops?(2)).to be(false)
        end

        it "drops nothing when neither +only:+ nor +except:+ is supplied" do
          filter = SerializersCodeGen::Filter::Indexed.build({comments: {only: [:id]}}, field_index)
          field_count.times do |i|
            expect(filter.drops?(i)).to be(false)
          end
        end

        it "ignores names in +only:+ that do not appear in field_index" do
          filter = SerializersCodeGen::Filter::Indexed.build({only: [:f0, :unknown]}, field_index)
          expect(filter.drops?(0)).to be(false)
          expect(filter.drops?(1)).to be(true)
        end

        it "lets +only:+ win when both +only:+ and +except:+ reach Indexed.build directly (validation lives at Filter.wrap)" do
          # Per S14.3: caller-facing validation rejects co-supply at
          # +Filter.wrap+. +Indexed.build+ has no validator of its own —
          # if a future caller skips +Filter.wrap+, the resolution rule
          # below ("+:only+ wins") is the documented fallback. Pinned
          # so a refactor that moves validation downstream still
          # preserves the resolution rule it bypasses.
          filter = SerializersCodeGen::Filter::Indexed.build({only: [:f0], except: [:f1]}, field_index)
          expect(filter.drops?(0)).to be(false)
          expect(filter.drops?(1)).to be(true)
          expect(filter.drops?(2)).to be(true)
        end
      end

      describe "#none?" do
        it "returns false" do
          filter = SerializersCodeGen::Filter::Indexed.build({only: [:f0]}, field_index)
          expect(filter.none?).to be(false)
        end
      end

      describe "#child" do
        it "returns the same cached object on repeated calls within one call" do
          filter = SerializersCodeGen::Filter::Indexed.build({author: {only: [:id]}}, field_index)
          first = filter.child(:author)
          second = filter.child(:author)
          expect(first).to equal(second)
        end

        it "returns Filter::NONE for a Source not present in the caller hash" do
          filter = SerializersCodeGen::Filter::Indexed.build({only: [:f0]}, field_index)
          expect(filter.child(:author)).to equal(SerializersCodeGen::Filter::NONE)
        end

        it "returns Filter::NONE for a Source whose sub-hash is empty" do
          filter = SerializersCodeGen::Filter::Indexed.build({author: {}}, field_index)
          expect(filter.child(:author)).to equal(SerializersCodeGen::Filter::NONE)
        end

        it "returns Filter::NONE for a Source whose value is non-Hash (silently ignored)" do
          filter = SerializersCodeGen::Filter::Indexed.build({author: 123, comments: nil}, field_index)
          expect(filter.child(:author)).to equal(SerializersCodeGen::Filter::NONE)
          expect(filter.child(:comments)).to equal(SerializersCodeGen::Filter::NONE)
        end
      end
    end

    context "with the Bits representation (field_count = 5, fits in 63 bits)" do
      include_examples "an Indexed Filter representation", field_count: 5
    end

    context "with the Array representation (field_count = 70, exceeds 63 bits)" do
      include_examples "an Indexed Filter representation", field_count: 70
    end
  end

  describe "end-to-end via Generated Class" do
    def descriptor_with_attribute_names(names)
      SerializersCodeGen::Descriptor.new(
        name: "FilterEndToEnd_#{names.size}",
        models: nil,
        attributes: names.map { |n| SerializersCodeGen::Attribute.new(name: n, source: n) },
        method_attributes: [],
        associations: []
      )
    end

    it "serializes only the +only:+ Fields on a small Descriptor (Bits rep)" do
      descriptor = descriptor_with_attribute_names([:id, :title, :body])
      generated = SerializersCodeGen.compile(descriptor, output: :json).new(descriptor: descriptor)
      record = {"id" => 1, "title" => "hi", "body" => "long"}
      expect(generated.serialize_one(record, filters: {only: [:id]})).to eq('{"id":1}')
    end

    it "omits the +except:+ Fields on a small Descriptor (Bits rep)" do
      descriptor = descriptor_with_attribute_names([:id, :title, :body])
      generated = SerializersCodeGen.compile(descriptor, output: :json).new(descriptor: descriptor)
      record = {"id" => 1, "title" => "hi", "body" => "long"}
      expect(generated.serialize_one(record, filters: {except: [:body]})).to eq('{"id":1,"title":"hi"}')
    end

    it "exercises the Array representation on a Descriptor with > 63 Fields" do
      names = (1..70).map { |i| :"f#{i}" }
      descriptor = descriptor_with_attribute_names(names)
      generated = SerializersCodeGen.compile(descriptor, output: :json).new(descriptor: descriptor)
      record = names.each_with_object({}) { |n, h| h[n.to_s] = n.to_s }
      output = generated.serialize_one(record, filters: {only: [:f1, :f70]})
      expect(output).to eq('{"f1":"f1","f70":"f70"}')
    end

    it "exercises the Array representation in :hash mode on a > 63-Field Descriptor" do
      names = (1..70).map { |i| :"f#{i}" }
      descriptor = descriptor_with_attribute_names(names)
      generated = SerializersCodeGen.compile(descriptor, output: :hash).new(descriptor: descriptor)
      record = names.each_with_object({}) { |n, h| h[n.to_s] = n.to_s }
      output = generated.serialize_one(record, filters: {except: [:f1]})
      expect(output).not_to have_key("f1")
      expect(output["f2"]).to eq("f2")
      expect(output["f70"]).to eq("f70")
    end
  end
end
