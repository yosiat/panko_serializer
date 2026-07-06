# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "config/config_null_for_has_one_off"

RSpec.describe "Generated Class for Fixtures::ConfigNullForHasOneOff" do
  let(:descriptor) { Fixtures::ConfigNullForHasOneOff::DESCRIPTOR }
  let(:config) { Fixtures::ConfigNullForHasOneOff::CONFIG }

  describe "#serialize_one — has_one Source returning nil omits the key (null_for_missing_has_one: false)" do
    # Per-mode expected outputs lifted out of +let+ blocks so the
    # +RSpec/MultipleMemoizedHelpers+ cap (5) isn't exceeded — the
    # parity iteration already spends 4 on +descriptor+ + +config+ +
    # +generated_class+ + +generated+. Frozen so iteration mutations
    # can't drift across +it+s.
    expected_with_inner = {
      json: '{"id":1,"inner":{"id":7,"name":"alice"}}',
      hash: {"id" => 1, "inner" => {"id" => 7, "name" => "alice"}}.freeze
    }.freeze
    expected_omitted = {
      json: '{"id":1}',
      hash: {"id" => 1}.freeze
    }.freeze

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { Panko::CodeGen.compile(descriptor, output: mode, config: config) }
        let(:generated) { generated_class.new(descriptor: descriptor) }

        it "emits the key with the nested object when the Source returns a non-nil Record (Hash)" do
          record = {"id" => 1, "inner" => {"id" => 7, "name" => "alice"}}
          expect(generated.serialize_one(record)).to eq(expected_with_inner[mode])
        end

        it "emits the key with the nested object when the Source returns a non-nil Record (PORO)" do
          inner = Struct.new(:id, :name).new(7, "alice")
          record = Struct.new(:id, :inner).new(1, inner)
          expect(generated.serialize_one(record)).to eq(expected_with_inner[mode])
        end

        it "omits the key entirely when the Source returns nil (Hash record)" do
          record = {"id" => 1, "inner" => nil}
          expect(generated.serialize_one(record)).to eq(expected_omitted[mode])
        end

        it "omits the key entirely when the Source returns nil (PORO record)" do
          record = Struct.new(:id, :inner).new(1, nil)
          expect(generated.serialize_one(record)).to eq(expected_omitted[mode])
        end

        it "does not include the inner key as null when omitted (regression: distinguishes the omit branch from the default-null branch)" do
          record = {"id" => 1, "inner" => nil}
          output = generated.serialize_one(record)
          case mode
          when :json
            expect(output).not_to include('"inner":null')
            expect(output).not_to include('"inner"')
          when :hash
            expect(output).not_to have_key("inner")
          end
        end
      end
    end
  end
end
