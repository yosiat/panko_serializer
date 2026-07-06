# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "shallow_generic"
require "config/config_root_key_on"

# Cross-cutting Root Key contract — the 12-item enumeration from
# +docs/testing.md § root_key_spec.rb+. JSON/Hash parity is iterated at
# the describe block per +docs/testing.md § JSON/Hash parity+; the
# accepted-values rule (non-empty String or +nil+) lives in
# +docs/generated-class.md § serialize_one+ and +docs/config.md+.
#
# Fixture strategy per +testing.md § root_key_spec.rb § Fixture
# strategy+:
#
# - +supports_root_key: true+ cases reuse +config_root_key_on+ (#7).
#   Its snapshot +MODES = [:json]+ pins only the committed bytes; the
#   feature tier compiles the same Descriptor + Config in both modes
#   (Descriptor + Config are mode-orthogonal).
# - +supports_root_key: false+ cases use +shallow_generic+ (#1) with
#   default Config — the smallest fixture with the no-+root_key+
#   signature.
RSpec.describe "Root Key — supports_root_key + per-call kwarg contract" do
  def compile_with(fixture, mode)
    Panko::CodeGen.compile(fixture::DESCRIPTOR, output: mode, config: fixture::CONFIG)
      .new(descriptor: fixture::DESCRIPTOR)
  end

  describe "(1) serialize_one + root_key: \"post\" → wrapped" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "wraps the single-record output in {root_key => ...}" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          record = {"id" => 1}
          expected = (mode == :json) ? '{"post":{"id":1}}' : {"post" => {"id" => 1}}
          expect(generated.serialize_one(record, root_key: "post")).to eq(expected)
        end
      end
    end
  end

  describe "(2) serialize_many + root_key: \"posts\" → wrapped" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "wraps the array output in {root_key => [...]}" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          records = [{"id" => 1}, {"id" => 2}]
          expected = (mode == :json) ? '{"posts":[{"id":1},{"id":2}]}' : {"posts" => [{"id" => 1}, {"id" => 2}]}
          expect(generated.serialize_many(records, root_key: "posts")).to eq(expected)
        end
      end
    end
  end

  describe "(3) root_key: nil (explicit) → unwrapped" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "produces unwrapped output for serialize_one" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          record = {"id" => 1}
          expected = (mode == :json) ? '{"id":1}' : {"id" => 1}
          expect(generated.serialize_one(record, root_key: nil)).to eq(expected)
        end

        it "produces unwrapped output for serialize_many" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          records = [{"id" => 1}]
          expected = (mode == :json) ? '[{"id":1}]' : [{"id" => 1}]
          expect(generated.serialize_many(records, root_key: nil)).to eq(expected)
        end
      end
    end
  end

  describe "(4) root_key: kwarg omitted → unwrapped (default is nil)" do
    # Pinned separately from (3) to guard against a default drift —
    # changing the default away from +nil+ would silently start wrapping
    # by default.
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "produces unwrapped output for serialize_one when kwarg omitted" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          record = {"id" => 1}
          expected = (mode == :json) ? '{"id":1}' : {"id" => 1}
          expect(generated.serialize_one(record)).to eq(expected)
        end

        it "produces unwrapped output for serialize_many when kwarg omitted" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          records = [{"id" => 1}]
          expected = (mode == :json) ? '[{"id":1}]' : [{"id" => 1}]
          expect(generated.serialize_many(records)).to eq(expected)
        end
      end
    end
  end

  describe "(5) Per-call stability — same instance, successive calls with different root_keys" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "handles different root_keys across successive serialize_one calls" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          record = {"id" => 1}
          first_expected = (mode == :json) ? '{"post":{"id":1}}' : {"post" => {"id" => 1}}
          second_expected = (mode == :json) ? '{"latest_post":{"id":1}}' : {"latest_post" => {"id" => 1}}
          third_expected = (mode == :json) ? '{"id":1}' : {"id" => 1}
          expect(generated.serialize_one(record, root_key: "post")).to eq(first_expected)
          expect(generated.serialize_one(record, root_key: "latest_post")).to eq(second_expected)
          expect(generated.serialize_one(record)).to eq(third_expected)
        end

        it "handles different root_keys across successive serialize_many calls" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          records = [{"id" => 1}]
          first_expected = (mode == :json) ? '{"posts":[{"id":1}]}' : {"posts" => [{"id" => 1}]}
          second_expected = (mode == :json) ? '{"latest_posts":[{"id":1}]}' : {"latest_posts" => [{"id" => 1}]}
          expect(generated.serialize_many(records, root_key: "posts")).to eq(first_expected)
          expect(generated.serialize_many(records, root_key: "latest_posts")).to eq(second_expected)
        end
      end
    end
  end

  describe "(6) serialize_many + empty collection + root_key: → wrapped empty array" do
    # Pins +{"posts":[]}+ — never +null+, never omitted.
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "emits an empty array inside the wrap" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          expected = (mode == :json) ? '{"posts":[]}' : {"posts" => []}
          expect(generated.serialize_many([], root_key: "posts")).to eq(expected)
        end
      end
    end
  end

  describe "(7) root_key: \"\" → library ArgumentError" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "raises ArgumentError on serialize_one" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          expect {
            generated.serialize_one({"id" => 1}, root_key: "")
          }.to raise_error(ArgumentError, /root_key.*non-empty String/)
        end

        it "raises ArgumentError on serialize_many" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          expect {
            generated.serialize_many([{"id" => 1}], root_key: "")
          }.to raise_error(ArgumentError, /root_key.*non-empty String/)
        end
      end
    end
  end

  describe "(8) root_key: :post (Symbol) → library ArgumentError" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "raises ArgumentError on serialize_one (no auto-coercion to String)" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          expect {
            generated.serialize_one({"id" => 1}, root_key: :post)
          }.to raise_error(ArgumentError, /root_key.*non-empty String/)
        end

        it "raises ArgumentError on serialize_many" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          expect {
            generated.serialize_many([{"id" => 1}], root_key: :posts)
          }.to raise_error(ArgumentError, /root_key.*non-empty String/)
        end
      end
    end
  end

  describe "(9) root_key: 42 (non-String, non-nil) → library ArgumentError" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "raises ArgumentError on serialize_one" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          expect {
            generated.serialize_one({"id" => 1}, root_key: 42)
          }.to raise_error(ArgumentError, /root_key.*non-empty String/)
        end

        it "raises ArgumentError on serialize_many" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          expect {
            generated.serialize_many([{"id" => 1}], root_key: 42)
          }.to raise_error(ArgumentError, /root_key.*non-empty String/)
        end
      end
    end
  end

  describe "(9b) root_key: false (non-String, non-nil) → library ArgumentError" do
    # Regression: the original implementation gated validation on
    # +if root_key+ rather than +unless root_key.nil?+, so +false+
    # silently bypassed the check and was treated as "no wrap". Per
    # +docs/generated-class.md § serialize_one+ ("any non-String/non-nil
    # value raises +ArgumentError+"), +false+ must raise like any other
    # non-nil non-String value.
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "raises ArgumentError on serialize_one" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          expect {
            generated.serialize_one({"id" => 1}, root_key: false)
          }.to raise_error(ArgumentError, /root_key.*non-empty String/)
        end

        it "raises ArgumentError on serialize_many" do
          generated = compile_with(Fixtures::Config::ConfigRootKeyOn, mode)
          expect {
            generated.serialize_many([{"id" => 1}], root_key: false)
          }.to raise_error(ArgumentError, /root_key.*non-empty String/)
        end
      end
    end
  end

  describe "(10) supports_root_key: false + serialize_one(record, root_key:) → Ruby ArgumentError" do
    # The kwarg literally does not exist on the generated method. Ruby
    # itself raises +ArgumentError: unknown keyword: :root_key+ — not
    # the library validator, which is never even reached. Asserts the
    # message text shape so a future shift to a +**+ catch-all signature
    # would be caught.
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "raises Ruby's unknown-keyword ArgumentError" do
          generated = compile_with(Fixtures::ShallowGeneric, mode)
          expect {
            generated.serialize_one({"id" => 1, "title" => "hi"}, root_key: "post")
          }.to raise_error(ArgumentError, /unknown keyword.*root_key/)
        end
      end
    end
  end

  describe "(11) supports_root_key: false + serialize_many(records, root_key:) → Ruby ArgumentError" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "raises Ruby's unknown-keyword ArgumentError" do
          generated = compile_with(Fixtures::ShallowGeneric, mode)
          expect {
            generated.serialize_many([{"id" => 1, "title" => "hi"}], root_key: "posts")
          }.to raise_error(ArgumentError, /unknown keyword.*root_key/)
        end
      end
    end
  end

  describe "(12) supports_root_key: false + no root_key → unwrapped output" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "produces normal output without any wrap" do
          generated = compile_with(Fixtures::ShallowGeneric, mode)
          record = {"id" => 1, "title" => "hi"}
          expected = Fixtures::ShallowGeneric.expected_output(mode)
          expect(generated.serialize_one(record)).to eq(expected)
        end

        it "produces normal output for serialize_many without any wrap" do
          generated = compile_with(Fixtures::ShallowGeneric, mode)
          records = [{"id" => 1, "title" => "hi"}]
          expected = (mode == :json) ? '[{"id":1,"title":"hi"}]' : [{"id" => 1, "title" => "hi"}]
          expect(generated.serialize_many(records)).to eq(expected)
        end
      end
    end
  end
end
