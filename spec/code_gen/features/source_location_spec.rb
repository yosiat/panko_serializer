# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "serializers_code_gen"
require "shallow_generic"

# Feature-tier coverage for the synthetic-path / real-path
# +Method#source_location+ split per S15.3 (issue #75).
#
# Architectural decision (recorded on issue #75 + PRD #67): no
# source-level substitution token. The +Generator+'s emitted bytes
# contain no path reference — paths only enter at materialization.
# +Compiler+ passes the synthetic +(serializers-code-gen:
# <Name>/<output>)+ string as +module_eval+'s second argument, so
# in-memory classes report the synthetic path on
# +Method#source_location+. +Dump+ writes the bytes to disk via
# +File.write+; Ruby's +require+ then auto-stamps the real on-disk
# path on +Method#source_location+ when the dumped file loads. This
# is the lower-friction superset of the issue's two presupposed
# options (placeholder-token-and-substitute vs.
# inline-substitute-at-emit): neither is needed because the path
# never has to enter the source bytes — Ruby's standard
# materialization machinery (+module_eval+'s 2nd arg / +require+'s
# real-path attribution) does the job for both paths, and the
# byte-identity contract from +CLAUDE.md § Architectural shape+
# stays tight (every byte the +Generator+ emits is exactly what
# lands on disk; no post-emit substitution).
RSpec.describe "synthetic-path / real-path Method#source_location split" do
  let(:descriptor) { Fixtures::ShallowGeneric::DESCRIPTOR }
  let(:config) { Fixtures::ShallowGeneric::CONFIG }

  describe "Compile retains the synthetic path" do
    it "stamps +(serializers-code-gen: ShallowGenericSerializer/json)+ on a JSON-mode instance method" do
      klass = SerializersCodeGen.compile(descriptor, output: :json, config: config)
      path, line = klass.instance_method(:_write_one).source_location

      expect(path).to eq("(serializers-code-gen: ShallowGenericSerializer/json)")
      expect(line).to be_a(Integer).and(be_positive)
    end

    it "stamps +(serializers-code-gen: ShallowGenericSerializer/hash)+ on a Hash-mode instance method" do
      klass = SerializersCodeGen.compile(descriptor, output: :hash, config: config)
      path, line = klass.instance_method(:_to_hash).source_location

      expect(path).to eq("(serializers-code-gen: ShallowGenericSerializer/hash)")
      expect(line).to be_a(Integer).and(be_positive)
    end
  end

  describe "Dump-then-require reports the real on-disk path" do
    # Descriptor name is unique to this spec so the +require+ of a
    # dumped file defines a class that isn't already loaded from
    # +spec/fixtures/generated/+ — avoids method-redefinition warnings
    # when this spec runs in the same process as +snapshot_spec.rb+'s
    # tier-3 +require+ of the same fixture.
    let(:dumped_descriptor) { descriptor.with(name: "S15ThreeSyntheticPathFixture") }

    it "stamps the real File path on a JSON-mode dumped instance method" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "s15_three_synthetic_path_fixture_json.rb")
        SerializersCodeGen.dump(dumped_descriptor, output: :json, config: config, path: target)

        require target
        klass = Object.const_get(:S15ThreeSyntheticPathFixture_JSON)
        path, line = klass.instance_method(:_write_one).source_location

        expect(path).to eq(File.realpath(target))
        expect(line).to be_a(Integer).and(be_positive)
      end
    end

    it "stamps the real File path on a Hash-mode dumped instance method" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "s15_three_synthetic_path_fixture_hash.rb")
        SerializersCodeGen.dump(dumped_descriptor, output: :hash, config: config, path: target)

        require target
        klass = Object.const_get(:S15ThreeSyntheticPathFixture_Hash)
        path, line = klass.instance_method(:_to_hash).source_location

        expect(path).to eq(File.realpath(target))
        expect(line).to be_a(Integer).and(be_positive)
      end
    end
  end
end
