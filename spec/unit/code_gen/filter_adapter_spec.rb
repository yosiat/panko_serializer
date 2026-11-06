# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen/filter_adapter"

# Panko allows :only and :except at one level; the engine Filter does not. Translating lets a
# per-call filter reuse the cached Generated Class instead of compiling a narrowed Descriptor.
describe Panko::CodeGen::FilterAdapter do
  def adapt(only, except)
    described_class.to_engine_filters(only, except)
  end

  describe "attribute-level filters" do
    it "maps a bare only Array to an :only level" do
      expect(adapt([:name, :email], nil)).to eq(only: [:name, :email])
    end

    it "maps a bare except Array to an :except level" do
      expect(adapt(nil, [:password])).to eq(except: [:password])
    end

    it "returns an empty Hash when neither filter is given" do
      expect(adapt(nil, nil)).to eq({})
    end

    it "treats empty Arrays as no filter (Panko skips empty only/except)" do
      expect(adapt([], [])).to eq({})
    end
  end

  describe "only/except co-supplied at the same level" do
    it "collapses to :only with the excepted names removed" do
      expect(adapt([:name, :email, :phone], [:email])).to eq(only: [:name, :phone])
    end

    it "keeps an empty whitelist when except cancels the whole only list" do
      # The engine expresses "keep nothing" as an empty :only, not as no filter.
      expect(adapt([:name], [:name])).to eq(only: [])
    end
  end

  describe "the :instance convention (Hash-form current level)" do
    it "reads the current level from :instance and keeps association keys" do
      expect(adapt({instance: [:name], posts: [:title]}, nil))
        .to eq(only: [:name], posts: {only: [:title]})
    end

    it "omits the current level :only when :instance is absent" do
      expect(adapt({posts: [:title]}, nil)).to eq(posts: {only: [:title]})
    end
  end

  describe "nested association sub-filters" do
    it "recurses through Hash-valued association filters" do
      panko = {instance: [:name], posts: {instance: [:title], comments: [:body]}}
      expect(adapt(panko, nil))
        .to eq(only: [:name], posts: {only: [:title], comments: {only: [:body]}})
    end

    it "maps a Hash-form except through the same shape" do
      expect(adapt(nil, {instance: [:secret], posts: [:draft]}))
        .to eq(except: [:secret], posts: {except: [:draft]})
    end
  end

  describe "invalid filter types" do
    it "raises ArgumentError for a non-Array/Hash only" do
      expect { adapt("nope", nil) }.to raise_error(ArgumentError, /Array or Hash/)
    end

    it "raises ArgumentError for a non-Array/Hash except" do
      expect { adapt(nil, 123) }.to raise_error(ArgumentError, /Array or Hash/)
    end
  end

  describe "only and except spanning different keys" do
    it "merges association keys from both only and except" do
      only = {instance: [:name], posts: [:title]}
      except = {comments: [:ip]}
      expect(adapt(only, except))
        .to eq(only: [:name], posts: {only: [:title]}, comments: {except: [:ip]})
    end
  end
end
