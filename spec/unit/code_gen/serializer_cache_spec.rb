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
      klass._cg_compiled_json = nil
      klass._cg_compiled_hash = nil
      klass._cg_descriptor = nil
      klass._cg_pool_json = nil
      klass._cg_pool_hash = nil
      klass._cg_has_filters_for = nil
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

  it "stores the compiled class on the serializer's per-mode slot" do
    compiled = fetch(SerializerCacheFooSerializer, :json)

    expect(SerializerCacheFooSerializer._cg_compiled_json).to be(compiled)
  end

  it "subclasses the user serializer (parent_class dispatch)" do
    expect(fetch(SerializerCacheFooSerializer, :json).ancestors).to include(SerializerCacheFooSerializer)
  end

  it "raises on an unknown output mode" do
    expect { fetch(SerializerCacheFooSerializer, :xml) }.to raise_error(ArgumentError, /unknown output mode/)
  end
end
