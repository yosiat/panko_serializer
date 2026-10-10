# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "panko/code_gen"
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
require "config/config_json_column_non_json_specialized"

RSpec.describe "Panko::CodeGen.dump (Environment loads + runs)" do
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
    Fixtures::Config::ConfigJsonColumnNonJsonSpecialized
  ]

  # New names, so the dumped constants do not collide with the ones snapshot_spec.rb loads.
  # Keyed by object id, so a recursive tree gets one renamed copy per Descriptor.
  rename_tree = lambda do |descriptor, prefix, cache = {}|
    cached = cache[descriptor.__id__]
    next cached if cached

    renamed = Panko::CodeGen::Descriptor.new(
      name: "#{prefix}#{descriptor.name}",
      model: descriptor.model,
      parent_class: Fixtures::BaseSerializer,
      attributes: descriptor.attributes,
      method_attributes: descriptor.method_attributes,
      associations: []
    )
    cache[descriptor.__id__] = renamed

    descriptor.associations.each do |assoc|
      target = rename_tree.call(assoc.descriptor, prefix, cache)
      renamed.associations << Panko::CodeGen::Association.new(
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
            outer_basename = Panko::CodeGen::Generators::Fanout.basename_for(descriptor, mode)
            constant_name = "#{descriptor.name}_#{Panko::CodeGen::Compiler::OUTPUT_SUFFIXES.fetch(mode)}"

            Dir.mktmpdir do |dir|
              target = File.join(dir, outer_basename)
              Panko::CodeGen.dump(descriptor, output: mode, config: config, path: target)

              # Mutual-recursion files +require_relative+ each other, so silence Ruby's circular require warning.
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
