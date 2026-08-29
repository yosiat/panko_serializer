# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "panko/code_gen"
require "shallow_generic"

# Cross-cutting +Method#source_location+ contract — paths enter at
# materialization, not in +Generator+'s emitted bytes. +Compiler+
# passes the synthetic +(Panko::CodeGen: <Name>/<output>)+
# string as +module_eval+'s second argument; +Dump+ writes the bytes
# via +File.write+ and Ruby's +require+ auto-stamps the on-disk path
# when the file loads.
RSpec.describe "synthetic-path / real-path Method#source_location split" do
  let(:descriptor) { Fixtures::ShallowGeneric::DESCRIPTOR }
  let(:config) { Fixtures::ShallowGeneric::CONFIG }

  describe "Compile retains the synthetic path" do
    it "stamps +(Panko::CodeGen: ShallowGenericSerializer/json)+ on a JSON-mode instance method" do
      klass = Panko::CodeGen.compile(descriptor, output: :json, config: config)
      path, line = klass.instance_method(:_write_one).source_location

      expect(path).to eq("(Panko::CodeGen: ShallowGenericSerializer/json)")
      expect(line).to be_a(Integer).and(be_positive)
    end

    it "stamps +(Panko::CodeGen: ShallowGenericSerializer/hash)+ on a Hash-mode instance method" do
      klass = Panko::CodeGen.compile(descriptor, output: :hash, config: config)
      path, line = klass.instance_method(:_to_hash).source_location

      expect(path).to eq("(Panko::CodeGen: ShallowGenericSerializer/hash)")
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
        Panko::CodeGen.dump(dumped_descriptor, output: :json, config: config, path: target)

        require target
        klass = Object.const_get(:S15ThreeSyntheticPathFixture_JSON)
        path, line = klass.instance_method(:_write_one).source_location

        expect(File.realpath(path)).to eq(File.realpath(target))
        expect(line).to be_a(Integer).and(be_positive)
      end
    end

    it "stamps the real File path on a Hash-mode dumped instance method" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "s15_three_synthetic_path_fixture_hash.rb")
        Panko::CodeGen.dump(dumped_descriptor, output: :hash, config: config, path: target)

        require target
        klass = Object.const_get(:S15ThreeSyntheticPathFixture_Hash)
        path, line = klass.instance_method(:_to_hash).source_location

        expect(File.realpath(path)).to eq(File.realpath(target))
        expect(line).to be_a(Integer).and(be_positive)
      end
    end
  end
end
