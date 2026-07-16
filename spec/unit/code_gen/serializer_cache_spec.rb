# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "panko/code_gen/serializer_cache"

class SerializerCacheFooSerializer < Panko::Serializer
  attributes :id, :name
end

class SerializerCacheBarSerializer < Panko::Serializer
  attributes :id
end

describe Panko::CodeGen::SerializerCache do
  before do
    [SerializerCacheFooSerializer, SerializerCacheBarSerializer].each do |klass|
      described_class.reset!(klass)
    end
  end

  def fetch(serializer, output)
    described_class.fetch(serializer, output: output)
  end

  it "compiles and returns a Generated Class per output mode" do
    expect(fetch(SerializerCacheFooSerializer, :json)).to be_a(Class)
    expect(fetch(SerializerCacheFooSerializer, :hash)).to be_a(Class)
  end

  it "memoizes: the same (class, mode) returns the identical object" do
    first = fetch(SerializerCacheFooSerializer, :json)
    second = fetch(SerializerCacheFooSerializer, :json)

    expect(second).to be(first)
  end

  it "compiles distinct classes for :json and :hash" do
    expect(fetch(SerializerCacheFooSerializer, :json))
      .not_to be(fetch(SerializerCacheFooSerializer, :hash))
  end

  it "compiles distinct classes for distinct serializers" do
    expect(fetch(SerializerCacheFooSerializer, :json))
      .not_to be(fetch(SerializerCacheBarSerializer, :json))
  end

  it "subclasses the user serializer (parent_class dispatch)" do
    expect(fetch(SerializerCacheFooSerializer, :json).ancestors).to include(SerializerCacheFooSerializer)
  end

  it "raises on an unknown output mode" do
    expect { fetch(SerializerCacheFooSerializer, :xml) }.to raise_error(ArgumentError, /unknown output mode/)
  end

  describe ".reset!" do
    it "clears the compile cache so the next fetch compiles a fresh Generated Class" do
      first = fetch(SerializerCacheFooSerializer, :json)

      described_class.reset!(SerializerCacheFooSerializer)

      expect(fetch(SerializerCacheFooSerializer, :json)).not_to be(first)
    end

    it "clears both modes' pools" do
      json_pool = described_class.instance_pool(SerializerCacheFooSerializer, :json)
      hash_pool = described_class.instance_pool(SerializerCacheFooSerializer, :hash)

      described_class.reset!(SerializerCacheFooSerializer)

      expect(described_class.instance_pool(SerializerCacheFooSerializer, :json)).not_to be(json_pool)
      expect(described_class.instance_pool(SerializerCacheFooSerializer, :hash)).not_to be(hash_pool)
    end
  end

  describe ".specialized? / .variant_models" do
    before do
      Temping.create(:cache_specialized_host) do
        with_columns do |t|
          t.string :name
        end
      end
    end

    it "reports a compiled variant for an eligible AR record class" do
      described_class.variant_pool(SerializerCacheFooSerializer, :json, CacheSpecializedHost)

      expect(described_class.specialized?(SerializerCacheFooSerializer, :json, CacheSpecializedHost)).to be(true)
      expect(described_class.variant_models(SerializerCacheFooSerializer, :json)).to include(CacheSpecializedHost)
    end

    it "reports no variant for an ineligible record class, and stores nothing" do
      described_class.variant_pool(SerializerCacheFooSerializer, :json, Hash)

      expect(described_class.specialized?(SerializerCacheFooSerializer, :json, Hash)).to be(false)
      expect(described_class.variant_models(SerializerCacheFooSerializer, :json)).not_to include(Hash)
    end

    it "reports no variant before first sight" do
      expect(described_class.specialized?(SerializerCacheFooSerializer, :json, CacheSpecializedHost)).to be(false)
      expect(described_class.variant_models(SerializerCacheFooSerializer, :json)).to be_empty
    end
  end

  describe ".variant_pool — first-sight compile failures" do
    before do
      Temping.create(:cache_host) do
        with_columns do |t|
          t.string :name
        end
      end
    end

    let(:transient_error) { ActiveRecord::StatementInvalid.new("connection lost") }

    it "returns the base pool unstored on a transient AR error, then retries and admits" do
      base = described_class.instance_pool(SerializerCacheBarSerializer, :json)

      allow(Panko::CodeGen).to receive(:compile).and_raise(transient_error)
      pool = described_class.variant_pool(SerializerCacheBarSerializer, :json, CacheHost)

      expect(pool).to be(base)
      expect(described_class.variant_models(SerializerCacheBarSerializer, :json)).not_to include(CacheHost)

      allow(Panko::CodeGen).to receive(:compile).and_call_original
      retried = described_class.variant_pool(SerializerCacheBarSerializer, :json, CacheHost)

      expect(retried).not_to be(base)
      expect(described_class.variant_pool(SerializerCacheBarSerializer, :json, CacheHost)).to be(retried)
      expect(described_class.specialized?(SerializerCacheBarSerializer, :json, CacheHost)).to be(true)
    end
  end
end
