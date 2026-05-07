# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "serializers_code_gen"
require "shallow_generic"
require "shallow_specialized"
require "sti_specialized"
require "nested_composition"
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

# Environment loads-and-runs tier per +docs/dumping.md § Contract:
# the dumped file is runnable with a Descriptor at construction+. For
# every (fixture, mode), {SerializersCodeGen.dump} writes a +.rb+ file
# tree to a tmp dir, the spec +require+s the outer file, instantiates
# the resulting +Generated Class+ with the fixture's structural shape,
# and asserts +serialize_one(sanity_record)+ matches +expected_output(mode)+.
# Tier 1 (+Generator#emit+) and tier 2 (Dump byte-equality with snapshots)
# live in +spec/generators/snapshot_spec.rb+; this is tier 3 for the
# dumped form (the snapshot-loaded variant lives in +snapshot_spec.rb+).
#
# Each fixture's +Descriptor+ tree is renamed with a per-spec prefix so
# the dumped +Generated Class+ constants don't collide with the canonical
# constants the snapshot-tier +require+ defines from
# +spec/fixtures/generated/+. Renaming preserves the structural shape
# (Models, Attributes, MethodAttributes, Associations, +if:+ guards)
# verbatim, so the serialized output stays equal to +expected_output(mode)+.
RSpec.describe "SerializersCodeGen.dump (Environment loads + runs)" do
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
    Fixtures::Config::ConfigJsonColumnNonUniformSpecialized
  ]

  # Recursively renames every +Descriptor+ in +descriptor+'s tree with
  # +prefix+ + the original +Descriptor#name+. Identity-keyed so self-
  # and mutual-recursive trees collapse to one renamed instance per
  # unique source +Descriptor+ — same pattern as
  # +Generators::CycleMembership+ / +Generators::Fanout+.
  rename_tree = lambda do |descriptor, prefix, cache = {}|
    cached = cache[descriptor.__id__]
    next cached if cached

    renamed = SerializersCodeGen::Descriptor.new(
      name: "#{prefix}#{descriptor.name}",
      models: descriptor.models,
      attributes: descriptor.attributes,
      method_attributes: descriptor.method_attributes,
      associations: []
    )
    cache[descriptor.__id__] = renamed

    descriptor.associations.each do |assoc|
      target = rename_tree.call(assoc.descriptor, prefix, cache)
      renamed.associations << SerializersCodeGen::Association.new(
        name: assoc.name, kind: assoc.kind,
        descriptor: target, source: assoc.source, if: assoc.if
      )
    end
    renamed
  end

  fixtures.each do |fixture|
    describe fixture.name do
      fixture::MODES.each do |mode|
        context "with #{mode} Output Mode" do
          let(:descriptor) { rename_tree.call(fixture::DESCRIPTOR, "S15SixDumpRuns") }
          let(:config) { fixture::CONFIG }

          it "dump → require → .new(descriptor:) → serialize_one matches expected_output" do
            outer_basename = SerializersCodeGen::Generators::Fanout.basename_for(descriptor, mode)
            constant_name = "#{descriptor.name}_#{SerializersCodeGen::Compiler::OUTPUT_SUFFIXES.fetch(mode)}"

            Dir.mktmpdir do |dir|
              target = File.join(dir, outer_basename)
              SerializersCodeGen.dump(descriptor, output: mode, config: config, path: target)

              # Mutual-recursion fixtures wire +require_relative+
              # both ways across the cycle peers; Ruby's "circular
              # require considered harmful" warning is a load-time
              # heads-up, not a correctness failure (the cycle resolves
              # at +.new+, not at load), so silence it here per the
              # +docs/dumping.md § Nested Descriptor dumps+ contract.
              previous_verbose = $VERBOSE
              $VERBOSE = nil
              begin
                require target
              ensure
                $VERBOSE = previous_verbose
              end

              generated_class = Object.const_get(constant_name)
              instance = generated_class.new(descriptor: descriptor)
              expect(instance.serialize_one(fixture.sanity_record)).to eq(fixture.expected_output(mode))
            end
          end
        end
      end
    end
  end
end
