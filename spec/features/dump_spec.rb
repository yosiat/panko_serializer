# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

describe "Panko::CodeGen.dump" do
  let(:foo_serializer_class) do
    Class.new(Panko::Serializer) do
      attributes :name, :address
    end
  end

  before { stub_const("FooSerializer", foo_serializer_class) }

  around do |example|
    Dir.mktmpdir do |dir|
      @dump_dir = dir
      example.run
    end
  end

  let(:dump_path) { File.join(@dump_dir, "foo_serializer.rb") }

  it "accepts the public descriptor and writes the generated source" do
    returned = Panko::CodeGen.dump(FooSerializer.descriptor, output: :json, path: dump_path)

    expect(returned).to eq(dump_path)
    source = File.read(dump_path)
    expect(source).to include("class ")
    expect(source).to include("name")
    expect(source).to include("address")
  end

  it "dumps a filtered view as the same source as the unfiltered one" do
    unfiltered_path = File.join(@dump_dir, "unfiltered.rb")
    filtered_path = File.join(@dump_dir, "filtered.rb")

    Panko::CodeGen.dump(FooSerializer.descriptor, output: :json, path: unfiltered_path)
    filtered_view = FooSerializer.new(only: [:name]).descriptor
    Panko::CodeGen.dump(filtered_view, output: :json, path: filtered_path)

    expect(File.read(filtered_path)).to eq(File.read(unfiltered_path))
  end

  it "still accepts the internal engine descriptor" do
    internal = Panko::CodeGen::SerializerCache.descriptor_for(FooSerializer)

    Panko::CodeGen.dump(internal, output: :hash, path: dump_path)

    expect(File.read(dump_path)).to include("name")
  end
end
