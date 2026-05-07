# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "serializers_code_gen"
require "shallow_generic"
require "shallow_specialized"

# Feature-tier coverage for the +SerializersCodeGen.dump+ flat-Descriptor
# round-trip and +path:+ validation contract per S15.2 (issue #72). This
# slice owns single-file output for Descriptors with no nested
# Associations; multi-file fan-out + +require_relative+ topology +
# Recursive Descriptor handling lands in S15.5, synthetic-path
# substitution lands in S15.3.
RSpec.describe "SerializersCodeGen.dump (flat single-file)" do
  let(:descriptor) { Fixtures::ShallowGeneric::DESCRIPTOR }
  let(:config) { Fixtures::ShallowGeneric::CONFIG }

  describe "byte-equality with the committed snapshot" do
    [Fixtures::ShallowGeneric, Fixtures::ShallowSpecialized].each do |fixture|
      basename = fixture.name.split("::").last.gsub(/(?<=.)([A-Z])/, '_\1').downcase

      fixture::MODES.each do |mode|
        it "matches the snapshot for #{fixture.name} in #{mode} Output Mode" do
          snapshot_filename = "#{basename}_#{mode}.rb"
          snapshot_path = File.join(SerializersCodeGen::Spec::SNAPSHOTS_DIR, snapshot_filename)
          expected = File.read(snapshot_path)

          Dir.mktmpdir do |dir|
            target = File.join(dir, snapshot_filename)
            SerializersCodeGen.dump(
              fixture::DESCRIPTOR,
              output: mode,
              config: fixture::CONFIG,
              path: target
            )
            expect(File.read(target)).to eq(expected)
          end
        end
      end
    end
  end

  describe "path: validation" do
    it "raises ArgumentError when path: is nil" do
      expect {
        SerializersCodeGen.dump(descriptor, output: :json, config: config, path: nil)
      }.to raise_error(ArgumentError, /path:/)
    end

    it "raises ArgumentError when path: is an empty String" do
      expect {
        SerializersCodeGen.dump(descriptor, output: :json, config: config, path: "")
      }.to raise_error(ArgumentError, /path:/)
    end

    it "raises ArgumentError when path: is a Symbol" do
      expect {
        SerializersCodeGen.dump(descriptor, output: :json, config: config, path: :foo)
      }.to raise_error(ArgumentError, /path:/)
    end

    it "raises ArgumentError when path: is an Integer" do
      expect {
        SerializersCodeGen.dump(descriptor, output: :json, config: config, path: 42)
      }.to raise_error(ArgumentError, /path:/)
    end

    it "does not run the Validator when path: is invalid" do
      validator = instance_spy(SerializersCodeGen::Validators::Validator)
      dump = SerializersCodeGen::Dump.new(
        descriptor, output: :json, config: config, path: nil, validator: validator
      )
      expect { dump.dump }.to raise_error(ArgumentError)
      expect(validator).not_to have_received(:validate)
    end

    it "does not run the Generator when path: is invalid" do
      generator = instance_spy(SerializersCodeGen::Generator)
      dump = SerializersCodeGen::Dump.new(
        descriptor, output: :json, config: config, path: "", generator: generator
      )
      expect { dump.dump }.to raise_error(ArgumentError)
      expect(generator).not_to have_received(:emit)
    end

    it "writes no file when path: is invalid (no partial-write side effect)" do
      Dir.mktmpdir do |dir|
        [nil, "", :symbol, 42].each do |bogus|
          expect {
            SerializersCodeGen.dump(descriptor, output: :json, config: config, path: bogus)
          }.to raise_error(ArgumentError)
        end
        expect(Dir.children(dir)).to be_empty
      end
    end
  end

  describe "successful write" do
    it "returns the caller-supplied path:" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "shallow_generic_json.rb")
        result = SerializersCodeGen.dump(descriptor, output: :json, config: config, path: target)
        expect(result).to eq(target)
      end
    end

    it "writes a file at the caller-supplied path:" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "shallow_generic_json.rb")
        SerializersCodeGen.dump(descriptor, output: :json, config: config, path: target)
        expect(File).to exist(target)
      end
    end

    it "uses Config.new as the default when config: is omitted" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "shallow_generic_json.rb")
        SerializersCodeGen.dump(descriptor, output: :json, path: target)
        expect(File).to exist(target)
      end
    end
  end
end
