# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"
require "shallow_generic"

RSpec.describe "Generated Class for Fixtures::ShallowGeneric" do
  let(:descriptor) { Fixtures::ShallowGeneric::DESCRIPTOR }
  let(:config) { Fixtures::ShallowGeneric::CONFIG }
  let(:generated_class) { SerializersCodeGen.compile(descriptor, output: :json, config: config) }

  describe "#serialize_one" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { SerializersCodeGen.compile(descriptor, output: mode, config: config) }
        let(:expected) { Fixtures::ShallowGeneric.expected_output(mode) }

        it "serializes a Hash record (string keys)" do
          generated = generated_class.new(descriptor: descriptor)
          record = {"id" => 1, "title" => "hi"}
          expect(generated.serialize_one(record)).to eq(expected)
        end

        it "serializes a PORO Record (Struct)" do
          generated = generated_class.new(descriptor: descriptor)
          record = Struct.new(:id, :title).new(1, "hi")
          expect(generated.serialize_one(record)).to eq(expected)
        end

        it "serializes a Hash record passing context: nil explicitly" do
          generated = generated_class.new(descriptor: descriptor)
          record = {"id" => 1, "title" => "hi"}
          expect(generated.serialize_one(record, context: nil)).to eq(expected)
        end

        it "returns the expected output when filters: nil is passed explicitly (no-filter path stays usable)" do
          generated = generated_class.new(descriptor: descriptor)
          record = {"id" => 1, "title" => "hi"}
          expect(generated.serialize_one(record, filters: nil)).to eq(expected)
        end

        it "raises NotImplementedError when filters: is a non-nil Hash with :only" do
          generated = generated_class.new(descriptor: descriptor)
          record = {"id" => 1, "title" => "hi"}
          expect {
            generated.serialize_one(record, filters: {only: [:id]})
          }.to raise_error(NotImplementedError)
        end

        it "raises NotImplementedError when filters: is an empty Hash (any non-nil triggers the raise)" do
          generated = generated_class.new(descriptor: descriptor)
          record = {"id" => 1, "title" => "hi"}
          expect {
            generated.serialize_one(record, filters: {})
          }.to raise_error(NotImplementedError)
        end
      end
    end
  end

  describe "#serialize_many" do
    # Expected Array<Hash>/JSON-array output for the two-record corpus
    # used in the parity its below. Keyed by Output Mode so the iteration
    # picks the right shape inline without bloating per-context +let+
    # blocks (the +RSpec/MultipleMemoizedHelpers+ cap allows 5 cumulative;
    # the parity iteration already spends 2 on +generated_class+ +
    # +generated+).
    expected_pair = {
      json: '[{"id":1,"title":"hi"},{"id":2,"title":"yo"}]',
      hash: [{"id" => 1, "title" => "hi"}, {"id" => 2, "title" => "yo"}].freeze
    }.freeze
    expected_empty = {json: "[]", hash: [].freeze}.freeze

    # Single-record corpus for the filters: parity its below — kept
    # alongside +expected_pair+/+expected_empty+ so the per-mode expected
    # values stay close to the +it+s that read them. Frozen to avoid
    # accidental mutation across iterations.
    expected_single = {
      json: '[{"id":1,"title":"hi"}]',
      hash: [{"id" => 1, "title" => "hi"}].freeze
    }.freeze

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { SerializersCodeGen.compile(descriptor, output: mode, config: config) }
        let(:generated) { generated_class.new(descriptor: descriptor) }

        it "serializes an Array of Hash records" do
          records = [
            {"id" => 1, "title" => "hi"},
            {"id" => 2, "title" => "yo"}
          ]
          expect(generated.serialize_many(records)).to eq(expected_pair[mode])
        end

        it "serializes an empty Array to an empty collection" do
          expect(generated.serialize_many([])).to eq(expected_empty[mode])
        end

        it "serializes a mixed Array of Hash + PORO records via the per-element dispatcher" do
          records = [
            {"id" => 1, "title" => "hi"},
            Struct.new(:id, :title).new(2, "yo")
          ]
          expect(generated.serialize_many(records)).to eq(expected_pair[mode])
        end

        it "returns the expected output when filters: nil is passed explicitly (no-filter path stays usable)" do
          records = [{"id" => 1, "title" => "hi"}]
          expect(generated.serialize_many(records, filters: nil)).to eq(expected_single[mode])
        end

        it "raises NotImplementedError when filters: is a non-nil Hash with :only" do
          records = [{"id" => 1, "title" => "hi"}]
          expect {
            generated.serialize_many(records, filters: {only: [:id]})
          }.to raise_error(NotImplementedError)
        end

        it "raises NotImplementedError when filters: is an empty Hash (any non-nil triggers the raise)" do
          records = [{"id" => 1, "title" => "hi"}]
          expect {
            generated.serialize_many(records, filters: {})
          }.to raise_error(NotImplementedError)
        end
      end
    end
  end

  describe ".compile" do
    it "returns a fresh, independent class on each call" do
      first = SerializersCodeGen.compile(descriptor, output: :json, config: config)
      second = SerializersCodeGen.compile(descriptor, output: :json, config: config)
      expect(first).not_to equal(second)
    end

    it "returns a class whose instances respond to serialize_one" do
      expect(generated_class.new(descriptor: descriptor)).to respond_to(:serialize_one)
    end

    it "returns a Hash-mode class whose instances respond to serialize_one" do
      hash_class = SerializersCodeGen.compile(descriptor, output: :hash, config: config)
      expect(hash_class.new(descriptor: descriptor)).to respond_to(:serialize_one)
    end
  end

  describe "synthetic backtrace path" do
    it "stamps Method#source_location with (serializers-code-gen: <Name>/<mode>) for instance methods" do
      method = generated_class.instance_method(:_write_one)
      path, line = method.source_location
      expect(path).to eq("(serializers-code-gen: ShallowGenericSerializer/json)")
      expect(line).to be_a(Integer).and(be_positive)
    end

    it "stamps the Hash-mode synthetic path (.../hash) on a Hash-mode instance method" do
      hash_class = SerializersCodeGen.compile(descriptor, output: :hash, config: config)
      method = hash_class.instance_method(:_to_hash)
      path, line = method.source_location
      expect(path).to eq("(serializers-code-gen: ShallowGenericSerializer/hash)")
      expect(line).to be_a(Integer).and(be_positive)
    end
  end

  describe "frozen-string-literal pragma" do
    %i[json hash].each do |mode|
      it "is the first line of the Generator emit output in #{mode} Output Mode" do
        source = SerializersCodeGen::Generator.new.emit(descriptor, output: mode, config: config)
        expect(source.lines.first.chomp).to eq("# frozen_string_literal: true")
      end
    end
  end
end
