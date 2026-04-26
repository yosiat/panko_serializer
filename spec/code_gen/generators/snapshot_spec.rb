# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"
require "shallow_generic"
require "nested_composition"
require "shallow_specialized"
require "sti_specialized"
require "recursive_self"
require "recursive_mutual"
require "config/config_root_key_on"
require "config/config_hash_record_key_symbol"
require "config/config_hash_output_key_symbol"

# Snapshot tier — the +Generator+ / +Dump+ byte-emit tier from
# +docs/testing.md § Three tests per (fixture, mode)+. Three tests per
# (fixture, mode):
#
# 1. +Generator#emit+ bytes equal the on-disk snapshot.
# 2. +SerializersCodeGen.dump(...)+ write equals the snapshot — pending
#    until S15 ships +Dump+.
# 3. The committed snapshot file loads + runs + serializes
#    +sanity_record+ to +expected_output(mode)+.
#
# This file iterates +FIXTURES × MODES+; in S2.1 the corpus is one
# +shallow_generic+ × one +:json+ row. S3 onwards extend +MODES+ and the
# fixture set.
RSpec.describe "Generator snapshot corpus" do
  fixtures = [
    Fixtures::ShallowGeneric,
    Fixtures::NestedComposition,
    Fixtures::ShallowSpecialized,
    Fixtures::StiSpecialized,
    Fixtures::RecursiveSelf,
    Fixtures::RecursiveMutual,
    Fixtures::Config::ConfigRootKeyOn,
    Fixtures::ConfigHashRecordKeySymbol,
    Fixtures::ConfigHashOutputKeySymbol
  ]

  fixtures.each do |fixture|
    # Snake-case slug derived from the fixture's last namespace segment —
    # +Fixtures::ShallowGeneric+ → +"shallow_generic"+. Joined with the
    # mode suffix to form the snapshot filename.
    basename = fixture.name.split("::").last.gsub(/(?<=.)([A-Z])/, '_\1').downcase

    describe fixture.name do
      fixture::MODES.each do |mode|
        context "with #{mode} Output Mode" do
          let(:descriptor) { fixture::DESCRIPTOR }
          let(:config) { fixture::CONFIG }
          let(:snapshot_filename) { "#{basename}_#{mode}.rb" }

          it "Generator#emit bytes equal the committed snapshot" do
            source = SerializersCodeGen::Generator.new.emit(descriptor, output: mode, config: config)
            expect(source).to match_snapshot(snapshot_filename)
          end

          it "SerializersCodeGen.dump write equals the snapshot" do
            skip "Dump (S15) not yet shipped"
          end

          it "snapshot file loads + runs + serializes sanity_record to expected_output" do
            require snapshot_filename.sub(/\.rb\z/, "")
            constant_name = "#{descriptor.name}_#{SerializersCodeGen::Compiler::OUTPUT_SUFFIXES.fetch(mode)}"
            generated_class = Object.const_get(constant_name)
            instance = generated_class.new(descriptor: descriptor)
            expect(instance.serialize_one(fixture.sanity_record)).to eq(fixture.expected_output(mode))
          end
        end
      end
    end
  end
end
