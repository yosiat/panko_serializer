# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

# Pins the Output Mode seam: one descriptor-walking emitter talks to the
# Sink interface, and exactly two adapters — JsonSink and HashSink —
# satisfy it. The interface list below IS the seam contract; an adapter
# that stops answering one of these (or answers with a divergent shape)
# fails here before any snapshot regenerates.
RSpec.describe "Output Mode Sink contract" do
  sink_interface = %i[
    output suffix entry_name generic_entry_name
    split_hash_helper split_object_helper entry_params
    emit_class_constants emit_serialize_one emit_serialize_many
    open_record close_record
    attribute specialized_attribute method_attribute association
  ]

  let(:adapters) do
    {
      json: Panko::CodeGen::Generators::JsonSink.new,
      hash: Panko::CodeGen::Generators::HashSink.new
    }
  end

  it "both adapters satisfy the full Sink interface" do
    adapters.each_value do |sink|
      sink_interface.each do |message|
        expect(sink).to respond_to(message), "#{sink.class} does not respond to ##{message}"
      end
    end
  end

  it "the adapters disagree only where the mode genuinely diverges" do
    json, hash = adapters.values_at(:json, :hash)
    expect(json.output).to eq(:json)
    expect(hash.output).to eq(:hash)
    expect(json.suffix).to eq("JSON")
    expect(hash.suffix).to eq("Hash")
    expect(json.entry_params).to eq("record, writer, context, scope, filters")
    expect(hash.entry_params).to eq("record, context, scope, filters")
  end

  describe "Generator.sink_for" do
    it "resolves the adapter for each Output Mode" do
      expect(Panko::CodeGen::Generator.sink_for(:json)).to be_a(Panko::CodeGen::Generators::JsonSink)
      expect(Panko::CodeGen::Generator.sink_for(:hash)).to be_a(Panko::CodeGen::Generators::HashSink)
    end

    it "raises ArgumentError for an unknown mode — the one dispatch home" do
      expect {
        Panko::CodeGen::Generator.sink_for(:xml)
      }.to raise_error(ArgumentError, /unknown output mode/)
    end
  end
end
