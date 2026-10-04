# frozen_string_literal: true

require "spec_helper"

describe "Panko.compile_all" do
  let(:title) { "Hello" }
  let(:body) { "World" }
  let(:post) { Post.create(title: title, body: body).reload }
  let(:expected) { {"title" => title, "body" => body} }
  let(:poro_class) { Struct.new(:title, :body) }

  before do
    Temping.create(:post) do
      with_columns do |t|
        t.string :title
        t.string :body
      end
    end
  end

  around do |example|
    original_enabled = Panko::Config.auto_specialization.enabled
    example.run
  ensure
    Panko::Config.auto_specialization.enabled = original_enabled
  end

  def define_serializer(name, parent = Panko::Serializer, &block)
    stub_const(name, Class.new(parent, &block))
  end

  context "with declared models" do
    let!(:serializer) do
      define_serializer("CompileAllPostSerializer") do
        models Post
        attributes :title, :body
      end
    end

    it "lists the serializer as compiled" do
      expect(Panko.compile_all.compiled).to include(serializer)
    end

    it "serializes the same output after compiling" do
      Panko.compile_all

      expect(post).to serialized_as(serializer, expected)
    end

    it "compiles only the requested modes" do
      result = Panko.compile_all(modes: [:json])

      expect(result.compiled).to include(serializer)
      expect(Oj.load(serializer.new.serialize_to_json(post))).to eq(expected)
    end

    it "lists a model left on the base as not specialized" do
      Panko::Config.auto_specialization.enabled = false

      expect(Panko.compile_all.not_specialized).to include(serializer => [Post])
    end
  end

  context "without declared models" do
    let!(:serializer) do
      define_serializer("CompileAllPlainSerializer") { attributes :title, :body }
    end

    it "lists the serializer as without models" do
      expect(Panko.compile_all.without_models).to include(serializer)
    end

    it "still serializes records" do
      Panko.compile_all

      expect(post).to serialized_as(serializer, expected)
    end
  end

  context "with a model that cannot be specialized" do
    let!(:serializer) do
      poro = poro_class
      define_serializer("CompileAllPoroSerializer") do
        models poro
        attributes :title, :body
      end
    end

    it "lists the model as not specialized" do
      expect(Panko.compile_all.not_specialized).to include(serializer => [poro_class])
    end

    it "serializes the model through the base" do
      Panko.compile_all

      expect(poro_class.new(title, body)).to serialized_as(serializer, expected)
    end
  end

  context "with a serializer whose base does not compile" do
    let!(:serializer) do
      define_serializer("CompileAllCollidingSerializer") do
        attributes :title
        aliases body: :title
      end
    end

    it "reports the compile error" do
      expect(Panko.compile_all.errors[serializer]).to be_a(Panko::CodeGen::NameCollisionError)
    end
  end

  context "with a serializer without fields" do
    let!(:serializer) { define_serializer("CompileAllAbstractSerializer") }

    it "leaves it out of the result" do
      result = Panko.compile_all
      visited = result.compiled + result.without_models + result.not_specialized.keys + result.errors.keys

      expect(visited).not_to include(serializer)
    end
  end

  context "with inherited models" do
    let!(:parent) do
      define_serializer("CompileAllParentSerializer") do
        models Post
        attributes :title
      end
    end

    it "compiles the subclass for the parent's models" do
      child = define_serializer("CompileAllChildSerializer", parent) { attributes :body }

      expect(Panko.compile_all.compiled).to include(child)
    end

    it "uses the subclass's own models when it declares them" do
      poro = poro_class
      child = define_serializer("CompileAllOverrideSerializer", parent) { models poro }

      expect(Panko.compile_all.not_specialized).to include(child => [poro_class])
    end
  end

  it "visits only user serializers when called again" do
    serializer = define_serializer("CompileAllRepeatSerializer") { attributes :title }
    first = Panko.compile_all
    second = Panko.compile_all

    expect(second.without_models).to include(serializer)
    expect(second.without_models - first.without_models).to be_empty
  end

  it "rejects an unknown mode" do
    expect { Panko.compile_all(modes: [:xml]) }.to raise_error(ArgumentError, /xml/)
  end

  it "rejects a models argument that is not a class" do
    expect { define_serializer("CompileAllBadModelsSerializer") { models "Post" } }
      .to raise_error(ArgumentError, /"Post"/)
  end
end
