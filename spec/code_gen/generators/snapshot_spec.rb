# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
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
require "config/config_null_for_has_one_off"
require "config/config_json_column_wire_format"
require "config/config_json_column_html_safe"
require "config/config_json_column_generic_fallthrough"
require "config/config_json_column_non_uniform_specialized"
require "scope_threading"

# Snapshot tier — the +Generator+ / +Dump+ byte-emit tier from
# +docs/testing.md § Three tests per (fixture, mode)+. Three tests per
# (fixture, mode):
#
# 1. +Generator#emit+ bytes equal the on-disk +<fixture>_<mode>.rb+
#    snapshot (the single-file concatenated form Compile evaluates via
#    +module_eval+).
# 2. +SerializersCodeGen.dump(...)+ writes one or more files whose
#    bytes equal the on-disk per-Generated-Class snapshots (one
#    +<descriptor_snake>_<mode>.rb+ snapshot per +Generated Class+
#    in the tree). Flat fixtures land in S15.4; nested + Recursive
#    fixtures land in S15.5 via the multi-file +require_relative+
#    fan-out from {Generators::Fanout}.
# 3. The committed +<fixture>_<mode>.rb+ snapshot file loads + runs
#    + serializes +sanity_record+ to +expected_output(mode)+.
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
    Fixtures::ConfigHashOutputKeySymbol,
    Fixtures::ConfigNullForHasOneOff,
    Fixtures::Config::ConfigJsonColumnWireFormat,
    Fixtures::Config::ConfigJsonColumnHtmlSafe,
    Fixtures::Config::ConfigJsonColumnGenericFallthrough,
    Fixtures::Config::ConfigJsonColumnNonUniformSpecialized,
    Fixtures::ScopeThreading
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
            if descriptor.associations.empty?
              Dir.mktmpdir do |tmpdir|
                target = File.join(tmpdir, snapshot_filename)
                SerializersCodeGen.dump(descriptor, output: mode, config: config, path: target)
                expect(File.read(target)).to match_snapshot(snapshot_filename)
              end
            else
              expected_files = SerializersCodeGen::Generators::Fanout.emit_files(
                descriptor, output: mode, config: config
              )
              Dir.mktmpdir do |tmpdir|
                outer = expected_files.find { |f| f[:descriptor].equal?(descriptor) }
                target = File.join(tmpdir, outer[:basename])
                SerializersCodeGen.dump(descriptor, output: mode, config: config, path: target)

                expected_files.each do |file|
                  written = File.join(tmpdir, file[:basename])
                  expect(File.read(written)).to match_snapshot(file[:basename])
                end
              end
            end
          end

          it "snapshot file loads + runs + serializes sanity_record to expected_output" do
            require snapshot_filename.sub(/\.rb\z/, "")
            constant_name = "#{descriptor.name}_#{SerializersCodeGen::Compiler::OUTPUT_SUFFIXES.fetch(mode)}"
            generated_class = Object.const_get(constant_name)
            instance = generated_class.new(descriptor: descriptor)
            kwargs = {}
            kwargs[:context] = fixture.sanity_context if fixture.respond_to?(:sanity_context)
            kwargs[:scope] = fixture.sanity_scope if fixture.respond_to?(:sanity_scope)
            expect(instance.serialize_one(fixture.sanity_record, **kwargs)).to eq(fixture.expected_output(mode))
          end
        end
      end
    end
  end
end
