# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "config/config_hash_record_key_symbol"

# Feature spec for the +config_hash_record_key_symbol+ config-isolation
# fixture (#9 in the Config-isolation fixtures). Pins the
# +Config#hash_record_key_type: :symbol+ knob's behavior end-to-end:
# Generic-path +_write_one_hash+ / +_to_hash_hash+ reads from the Hash
# record with Symbol keys instead of String keys. The snapshot tier pins
# the emitted +record[:id]+ shape; this file pins that the emitted shape
# actually serializes Symbol-keyed Hash records correctly. Compiles in
# both Output Modes — the knob lives in the Generic record-access path,
# which is identical across modes — even though the snapshot is JSON-only.
RSpec.describe "Generated Class for Fixtures::ConfigHashRecordKeySymbol" do
  let(:descriptor) { Fixtures::ConfigHashRecordKeySymbol::DESCRIPTOR }
  let(:config) { Fixtures::ConfigHashRecordKeySymbol::CONFIG }

  describe "#serialize_one with hash_record_key_type: :symbol" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { Panko::CodeGen.compile(descriptor, output: mode, config: config) }
        let(:generated) { generated_class.new(descriptor: descriptor) }

        it "reads from a Hash record with Symbol keys" do
          record = {id: 1, name: "Alice"}
          expected = (mode == :json) ? '{"id":1,"name":"Alice"}' : {"id" => 1, "name" => "Alice"}
          expect(generated.serialize_one(record)).to eq(expected)
        end

        it "still serializes a PORO Record (Struct) via the object-dispatch helper (knob is Hash-record-only)" do
          record = Struct.new(:id, :name).new(2, "Bob")
          expected = (mode == :json) ? '{"id":2,"name":"Bob"}' : {"id" => 2, "name" => "Bob"}
          expect(generated.serialize_one(record)).to eq(expected)
        end
      end
    end
  end

  describe "default String-key form is unaffected by this fixture" do
    let(:default_config) { Panko::CodeGen::Config.new }

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { Panko::CodeGen.compile(descriptor, output: mode, config: default_config) }
        let(:generated) { generated_class.new(descriptor: descriptor) }

        it "reads from a Hash record with String keys when compiled with the default Config" do
          record = {"id" => 1, "name" => "Alice"}
          expected = (mode == :json) ? '{"id":1,"name":"Alice"}' : {"id" => 1, "name" => "Alice"}
          expect(generated.serialize_one(record)).to eq(expected)
        end
      end
    end
  end
end
