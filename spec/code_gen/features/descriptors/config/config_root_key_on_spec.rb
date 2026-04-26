# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"
require "config/config_root_key_on"

# Per-fixture record-shape coverage for the +config_root_key_on+
# config-isolation fixture (#7 from
# +docs/testing.md § Config-isolation fixtures+). The snapshot tier
# (+spec/generators/snapshot_spec.rb+) pins the JSON-mode emit bytes;
# this file backs that snapshot pin with behavior assertions across
# Hash + PORO record shapes (per
# +docs/testing.md § Record-shape coverage+) and pins the +root_key:+
# wrap end-to-end against records (the cross-cutting Root Key contract
# itself lives in +spec/features/concerns/root_key_spec.rb+).
RSpec.describe "Generated Class for Fixtures::Config::ConfigRootKeyOn" do
  let(:descriptor) { Fixtures::Config::ConfigRootKeyOn::DESCRIPTOR }
  let(:config) { Fixtures::Config::ConfigRootKeyOn::CONFIG }

  describe "#serialize_one" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { SerializersCodeGen.compile(descriptor, output: mode, config: config) }
        let(:expected_unwrapped) { Fixtures::Config::ConfigRootKeyOn.expected_output(mode) }

        it "serializes a Hash record (string keys) without root_key" do
          generated = generated_class.new(descriptor: descriptor)
          expect(generated.serialize_one({"id" => 1})).to eq(expected_unwrapped)
        end

        it "serializes a PORO Record (Struct) without root_key" do
          generated = generated_class.new(descriptor: descriptor)
          record = Struct.new(:id).new(1)
          expect(generated.serialize_one(record)).to eq(expected_unwrapped)
        end

        it "wraps in root_key when supplied" do
          generated = generated_class.new(descriptor: descriptor)
          expected = (mode == :json) ? '{"post":{"id":1}}' : {"post" => {"id" => 1}}
          expect(generated.serialize_one({"id" => 1}, root_key: "post")).to eq(expected)
        end
      end
    end
  end

  describe "#serialize_many" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { SerializersCodeGen.compile(descriptor, output: mode, config: config) }
        let(:generated) { generated_class.new(descriptor: descriptor) }

        it "serializes an Array of Hash records without root_key" do
          records = [{"id" => 1}, {"id" => 2}]
          expected = (mode == :json) ? '[{"id":1},{"id":2}]' : [{"id" => 1}, {"id" => 2}]
          expect(generated.serialize_many(records)).to eq(expected)
        end

        it "wraps the collection in root_key when supplied" do
          records = [{"id" => 1}, {"id" => 2}]
          expected = (mode == :json) ? '{"posts":[{"id":1},{"id":2}]}' : {"posts" => [{"id" => 1}, {"id" => 2}]}
          expect(generated.serialize_many(records, root_key: "posts")).to eq(expected)
        end
      end
    end
  end
end
